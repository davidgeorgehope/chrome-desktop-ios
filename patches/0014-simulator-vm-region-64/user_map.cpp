// SPDX-License-Identifier: GPL-2.0-or-later

#include "user_map.hpp"

#include "uml_darwin_guest.h"
#include "address_layout.hpp"

#include <mach/mach.h>
#include <mach/vm_map.h>

#include <sys/mman.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <signal.h>
#include <unordered_map>
#include <vector>

namespace uml::memory {
namespace {

constexpr std::uint64_t guest_page = DARWIN_UML_GUEST_PAGE_SIZE;
constexpr std::uint64_t guest_limit = DARWIN_UML_GUEST_ADDRESS_LIMIT;
constexpr std::size_t maximum_slots = 32;
constexpr std::uint64_t low_host_keep = 16ULL << 30;     /* leave [0, 16 GiB) */

struct PageRecord final {
	void *host_source{};
	int protection{};
};

struct Slot final {
	unsigned long generation{};
	std::uint64_t host_base{};
	std::uint64_t offset{}; /* K = host_base - guest_base */
	std::vector<std::uint8_t> bits{};
	std::unordered_map<std::uint64_t, PageRecord> pages{};
	bool in_use{};
};

struct State final {
	std::mutex mutex;
	bool enabled{};
	bool initialized{};
	std::uint64_t guest_base{};
	std::uint64_t span{};
	unsigned span_shift{};
	std::uint64_t host_region{};
	std::uint64_t host_region_size{};
	std::size_t host_page{16384};
	std::size_t slot_count{};
	std::array<Slot, maximum_slots> slots{};
	std::array<std::atomic<unsigned long>, maximum_slots> published_generation{};
	std::unordered_map<unsigned long, std::size_t> generation_slot{};
	std::uint64_t remap_failures{};
	std::uint64_t slots_assigned{};
	struct sigaction previous_segv{};
	struct sigaction previous_bus{};
	bool handler_installed{};
	std::uint64_t installs{};
	std::uint64_t mixed_skips{};
	std::uint64_t unmaps{};
};

State &state() noexcept
{
	static State storage;
	return storage;
}

[[nodiscard]] bool env_flag_on(const char *name) noexcept
{
	const char *value = std::getenv(name);
	if (value == nullptr || value[0] == '\0' ||
	    std::strcmp(value, "0") == 0)
		return false;
	return true;
}

[[nodiscard]] unsigned log2_pow2(std::uint64_t value) noexcept
{
	unsigned shift = 0;
	while (value > 1U) {
		value >>= 1U;
		++shift;
	}
	return shift;
}


void reserve_exact(std::uint64_t address, std::uint64_t length) noexcept
{
	if (length == 0)
		return;
	(void)mmap(reinterpret_cast<void *>(address),
		static_cast<std::size_t>(length), PROT_NONE,
		MAP_FIXED | MAP_PRIVATE | MAP_ANON | MAP_NORESERVE, -1, 0);
}

[[nodiscard]] int host_prot(int protection) noexcept
{
	int prot = 0;
	if ((protection & (PROT_READ | PROT_EXEC)) != 0)
		prot |= PROT_READ;
	if ((protection & PROT_WRITE) != 0)
		prot |= PROT_WRITE;
	return prot;
}

[[nodiscard]] std::uint8_t access_bits(int protection) noexcept
{
	std::uint8_t bits = 0;
	if ((protection & (PROT_READ | PROT_EXEC)) != 0)
		bits |= 1U;
	if ((protection & PROT_WRITE) != 0)
		bits |= 2U;
	return bits;
}

/* 2 bits per host page: bit0 = read, bit1 = write. */
void set_bits(Slot &slot, std::uint64_t guest_aligned, std::uint8_t value) noexcept
{
	const auto &st = state();
	if (guest_aligned < st.guest_base ||
	    guest_aligned - st.guest_base >= st.span)
		return;
	const std::uint64_t index =
		(guest_aligned - st.guest_base) / st.host_page;
	const std::uint64_t bit = index * 2U;
	const std::uint64_t byte = bit / 8U;
	const unsigned shift = static_cast<unsigned>(bit % 8U);
	if (byte >= slot.bits.size())
		return;
	slot.bits[byte] = static_cast<std::uint8_t>(
		(slot.bits[byte] & ~(0x3U << shift)) | ((value & 0x3U) << shift));
}

struct Hole final {
	std::uint64_t start{};
	std::uint64_t end{};
};

void log_holes(const std::vector<Hole> &holes) noexcept
{
	dprintf(STDERR_FILENO, "UML_JIT_USER_MAP inventory (host page %zu):\n",
		state().host_page);
	for (const auto &hole : holes) {
		const std::uint64_t size = hole.end - hole.start;
		if (size < (1ULL << 30))
			continue;
		dprintf(STDERR_FILENO,
			"  hole 0x%llx-0x%llx (%llu GiB)\n",
			static_cast<unsigned long long>(hole.start),
			static_cast<unsigned long long>(hole.end),
			static_cast<unsigned long long>(size >> 30));
	}
}

[[nodiscard]] std::vector<Hole> inventory_holes() noexcept
{
	std::vector<Hole> holes;
	// vm_region_64 is available in the iOS Simulator SDK; mach_vm_region
	// is not (mach_vm.h is #error-unsupported on iPhoneSimulator).
	vm_address_t cursor = 0;
	const std::uint64_t cap = guest_limit;
	vm_address_t prev_end = 0;
	for (;;) {
		vm_size_t size = 0;
		vm_region_basic_info_data_64_t info{};
		mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
		mach_port_t object = MACH_PORT_NULL;
		const kern_return_t kr = vm_region_64(mach_task_self(), &cursor,
			&size, VM_REGION_BASIC_INFO_64,
			reinterpret_cast<vm_region_info_t>(&info), &count, &object);
		if (kr != KERN_SUCCESS) {
			if (prev_end < cap)
				holes.push_back({prev_end, cap});
			break;
		}
		if (cursor > prev_end)
			holes.push_back({prev_end, std::min<std::uint64_t>(cursor, cap)});
		const std::uint64_t region_end = cursor + size;
		prev_end = region_end;
		cursor = region_end;
		if (prev_end >= cap)
			break;
	}
	return holes;
}

[[nodiscard]] bool reserve_region(std::uint64_t address, std::uint64_t length) noexcept
{
	void *mapped = mmap(reinterpret_cast<void *>(address),
		static_cast<std::size_t>(length), PROT_NONE,
		MAP_PRIVATE | MAP_ANON | MAP_NORESERVE | MAP_FIXED, -1, 0);
	if (mapped == MAP_FAILED ||
	    reinterpret_cast<std::uintptr_t>(mapped) != address) {
		if (mapped != MAP_FAILED)
			(void)munmap(mapped, static_cast<std::size_t>(length));
		return false;
	}
	return true;
}

[[nodiscard]] bool try_place(std::uint64_t host, std::uint64_t span,
	std::size_t slots, std::uint64_t guest_base) noexcept
{
	auto &st = state();
	const std::uint64_t need = span * slots;
	if (!reserve_region(host, need)) {
		dprintf(STDERR_FILENO,
			"UML_JIT_USER_MAP: reserve 0x%llx + %llu GiB (%zu x %llu GiB) "
			"failed errno=%d\n",
			static_cast<unsigned long long>(host),
			static_cast<unsigned long long>(need >> 30), slots,
			static_cast<unsigned long long>(span >> 30), errno);
		return false;
	}
	st.guest_base = guest_base;
	st.span = span;
	st.span_shift = log2_pow2(span);
	st.host_region = host;
	st.host_region_size = need;
	st.slot_count = slots;
	const std::uint64_t pages = span / st.host_page;
	const std::size_t bit_bytes =
		static_cast<std::size_t>((pages * 2U + 7U) / 8U);
	for (std::size_t index = 0; index < st.slot_count; ++index) {
		auto &slot = st.slots[index];
		slot.host_base = host + index * span;
		slot.offset = slot.host_base - st.guest_base;
		slot.bits.assign(bit_bytes, 0);
		slot.in_use = false;
		slot.pages.clear();
		slot.generation = 0;
	}
	dprintf(STDERR_FILENO,
		"UML_JIT_USER_MAP: reserved %zu slots of %llu GiB at 0x%llx; "
		"guest window 0x%llx-0x%llx; slot0 K=0x%llx%s\n",
		st.slot_count,
		static_cast<unsigned long long>(st.span >> 30),
		static_cast<unsigned long long>(st.host_region),
		static_cast<unsigned long long>(st.guest_base),
		static_cast<unsigned long long>(st.guest_base + st.span),
		static_cast<unsigned long long>(st.slots[0].offset),
		st.slots[0].offset == 0 ? " (identity)" : "");
	return true;
}

[[nodiscard]] bool pick_and_reserve() noexcept
{
	auto &st = state();
	st.host_page = static_cast<std::size_t>(vm_page_size);
	if (st.host_page == 0 || (st.host_page & (st.host_page - 1U)) != 0)
		st.host_page = 16384;

	auto holes = inventory_holes();
	std::vector<Hole> usable;
	for (auto hole : holes) {
		if (hole.end <= low_host_keep)
			continue;
		if (hole.start < low_host_keep)
			hole.start = low_host_keep;
		hole.start = (hole.start + st.host_page - 1U) &
			~(static_cast<std::uint64_t>(st.host_page) - 1U);
		hole.end &= ~(static_cast<std::uint64_t>(st.host_page) - 1U);
		if (hole.end > guest_limit)
			hole.end = guest_limit;
		if (hole.end > hole.start)
			usable.push_back(hole);
	}
	log_holes(usable);

	/* Darwin refused an 8 TiB MAP_NORESERVE at 0x780000000000 (ENOMEM)
	 * even though mach_vm_region showed a 32 TiB hole above the native
	 * window. Try compact packs, high hole first, so musl PIE / stacks
	 * near 0x7fff... still fall in the guest window. */
	constexpr std::uint64_t spans[] = {
		32ULL << 30, 16ULL << 30, 8ULL << 30, 4ULL << 30, 1ULL << 30};
	constexpr std::size_t slot_counts[] = {32, 16, 8, 4};
	struct Candidate final {
		std::uint64_t host{};
		std::uint64_t span{};
		std::size_t slots{};
		std::uint64_t guest_base{};
		bool high{};
	};
	std::vector<Candidate> candidates;
	for (const auto span : spans) {
		for (const auto slots : slot_counts) {
			const std::uint64_t need = span * slots;
			for (const auto &hole : usable) {
				if (hole.end - hole.start < need)
					continue;
				const std::uint64_t guest_base = guest_limit - span;
				auto add = [&](std::uint64_t host) {
					if (host < hole.start || host + need > hole.end)
						return;
					if ((host & (span - 1U)) != 0)
						return;
					candidates.push_back({host, span, slots, guest_base,
						hole.end == guest_limit ||
							hole.start >= 0x600000000000ULL});
				};
				add(guest_base);
				add((hole.end - need) & ~(span - 1U));
				add((hole.start + span - 1U) & ~(span - 1U));
			}
		}
	}
	std::sort(candidates.begin(), candidates.end(),
		[](const Candidate &a, const Candidate &b) {
			if (a.high != b.high)
				return a.high && !b.high;
			if (a.span != b.span)
				return a.span > b.span;
			if (a.slots != b.slots)
				return a.slots > b.slots;
			return a.host > b.host;
		});
	std::vector<Candidate> unique;
	for (const auto &candidate : candidates) {
		if (!unique.empty() && unique.back().host == candidate.host &&
		    unique.back().span == candidate.span &&
		    unique.back().slots == candidate.slots)
			continue;
		unique.push_back(candidate);
	}
	for (const auto &candidate : unique) {
		if (try_place(candidate.host, candidate.span, candidate.slots,
			    candidate.guest_base))
			return true;
	}
	dprintf(STDERR_FILENO,
		"UML_JIT_USER_MAP: no mmapable pack in the inventoried holes\n");
	return false;
}

Slot *slot_for_generation_locked(unsigned long generation, bool assign) noexcept
{
	auto &st = state();
	if (const auto found = st.generation_slot.find(generation);
	    found != st.generation_slot.end())
		return &st.slots[found->second];
	if (!assign || generation == 0)
		return nullptr;
	for (std::size_t index = 0; index < st.slot_count; ++index) {
		if (st.slots[index].in_use)
			continue;
		st.slots[index].in_use = true;
		st.slots[index].generation = generation;
		st.slots[index].pages.clear();
		std::fill(st.slots[index].bits.begin(), st.slots[index].bits.end(),
			0);
		st.generation_slot.emplace(generation, index);
		st.published_generation[index].store(
			generation, std::memory_order_release);
		++st.slots_assigned;
		return &st.slots[index];
	}
	return nullptr;
}

void uninstall_host_page(Slot &slot, std::uint64_t guest_aligned) noexcept
{
	const auto &st = state();
	const std::uint64_t host = guest_aligned + slot.offset;
	reserve_exact(host, st.host_page);
	set_bits(slot, guest_aligned, 0);
}

[[nodiscard]] bool host_pages_uniform(const Slot &slot,
	std::uint64_t guest_aligned, void **source, int *protection) noexcept
{
	const auto &st = state();
	const std::size_t guests = st.host_page / guest_page;
	void *first = nullptr;
	int prot = 0;
	for (std::size_t index = 0; index < guests; ++index) {
		const auto guest = guest_aligned + index * guest_page;
		const auto found = slot.pages.find(guest);
		if (found == slot.pages.end())
			return false;
		if (index == 0) {
			first = found->second.host_source;
			prot = host_prot(found->second.protection);
			if (first == nullptr ||
			    (reinterpret_cast<std::uintptr_t>(first) % st.host_page) != 0)
				return false;
		} else {
			auto *expected = static_cast<std::byte *>(first) +
				index * guest_page;
			if (found->second.host_source != expected)
				return false;
			if (host_prot(found->second.protection) != prot)
				return false;
		}
	}
	if (prot == 0)
		return false;
	*source = first;
	*protection = prot;
	return true;
}

void refresh_span(Slot &slot, std::uint64_t address, std::uint64_t length) noexcept
{
	auto &st = state();
	if (length == 0)
		return;
	const std::uint64_t mask =
		~(static_cast<std::uint64_t>(st.host_page) - 1U);
	const std::uint64_t first = address & mask;
	const std::uint64_t last = (address + length - 1U) & mask;
	for (std::uint64_t guest = first; guest <= last; guest += st.host_page) {
		if (guest < st.guest_base || guest - st.guest_base >= st.span)
			continue;
		void *source = nullptr;
		int prot = 0;
		if (!host_pages_uniform(slot, guest, &source, &prot)) {
			if (slot.pages.empty()) {
				uninstall_host_page(slot, guest);
				continue;
			}
			/* A mixed or partial 16 KiB span stays on the software TLB. */
			uninstall_host_page(slot, guest);
			++st.mixed_skips;
			continue;
		}
		vm_address_t destination = static_cast<vm_address_t>(guest + slot.offset);
		vm_prot_t current = VM_PROT_NONE;
		vm_prot_t maximum = VM_PROT_NONE;
		const kern_return_t remap = vm_remap(mach_task_self(), &destination,
			st.host_page, 0, VM_FLAGS_FIXED | VM_FLAGS_OVERWRITE,
			mach_task_self(), reinterpret_cast<vm_address_t>(source),
			FALSE, &current, &maximum, VM_INHERIT_NONE);
		if (remap != KERN_SUCCESS ||
		    destination != static_cast<vm_address_t>(guest + slot.offset)) {
			uninstall_host_page(slot, guest);
			++st.remap_failures;
			continue;
		}
		int want = prot;
		if (vm_protect(mach_task_self(), destination, st.host_page,
			    FALSE, want) != KERN_SUCCESS) {
			want &= ~PROT_EXEC;
			if (want == 0 ||
			    vm_protect(mach_task_self(), destination, st.host_page,
				    FALSE, want) != KERN_SUCCESS) {
				uninstall_host_page(slot, guest);
				++st.remap_failures;
				continue;
			}
		}
		set_bits(slot, guest, access_bits(want));
		++st.installs;
	}
}

void apply_pages(unsigned long generation, std::uint64_t address,
	std::uint64_t length, void *host_source, int protection, bool present) noexcept
{
	auto &st = state();
	if (!st.enabled || length == 0)
		return;
	/* Kernel / native-window addresses are not in the guest user window. */
	if (address < st.guest_base || address - st.guest_base >= st.span) {
		if (address + length <= st.guest_base || address >= st.guest_base + st.span)
			return;
	}
	std::lock_guard lock{st.mutex};
	auto *slot = slot_for_generation_locked(generation, present);
	if (slot == nullptr)
		return;
	for (std::uint64_t pos = 0; pos < length; pos += guest_page) {
		const auto guest = address + pos;
		if (guest < st.guest_base || guest - st.guest_base >= st.span)
			continue;
		if (!present) {
			slot->pages.erase(guest);
		} else {
			auto *src = host_source == nullptr ? nullptr :
				static_cast<std::byte *>(host_source) + pos;
			slot->pages[guest] = PageRecord{src, protection};
		}
	}
	refresh_span(*slot, address, length);
	if (!present)
		++st.unmaps;
}

void handle_fault(int signo, siginfo_t *info, void *context)
{
	auto &st = state();
	const auto fault = info != nullptr ?
		reinterpret_cast<std::uintptr_t>(info->si_addr) : 0;
	bool retried = false;
	if (st.enabled && fault != 0 &&
	    fault >= st.host_region &&
	    fault < st.host_region + st.host_region_size) {
		const std::uint64_t offset = fault - st.host_region;
		const std::size_t index = static_cast<std::size_t>(offset / st.span);
		if (index < st.slot_count) {
			std::lock_guard lock{st.mutex};
			auto &slot = st.slots[index];
			if (slot.in_use) {
				const std::uint64_t guest = fault - slot.offset;
				const std::uint64_t aligned =
					guest & ~(static_cast<std::uint64_t>(st.host_page) - 1U);
				const auto before = st.installs;
				refresh_span(slot, aligned, st.host_page);
				retried = st.installs > before;
			}
		}
	}
	if (retried)
		return;
	struct sigaction *previous =
		signo == SIGBUS ? &st.previous_bus : &st.previous_segv;
	if ((previous->sa_flags & SA_SIGINFO) != 0 &&
	    previous->sa_sigaction != nullptr &&
	    previous->sa_sigaction != handle_fault)
		previous->sa_sigaction(signo, info, context);
	else if ((previous->sa_flags & SA_SIGINFO) == 0 &&
		 previous->sa_handler != nullptr &&
		 previous->sa_handler != SIG_DFL &&
		 previous->sa_handler != SIG_IGN)
		previous->sa_handler(signo);
	else {
		/* A fault in the reserved region that we could not install is a
		 * guest permission or missing-page event that should have taken
		 * the software TLB path (bitmap bit clear). Reaching here is a
		 * bug; restore the default so the process does not loop. */
		struct sigaction reset {};
		reset.sa_handler = SIG_DFL;
		(void)sigaction(signo, &reset, nullptr);
		(void)raise(signo);
	}
}

void install_handler() noexcept
{
	auto &st = state();
	struct sigaction action {};
	action.sa_sigaction = handle_fault;
	action.sa_flags = SA_SIGINFO | SA_RESTART;
	sigemptyset(&action.sa_mask);
	(void)sigaction(SIGSEGV, &action, &st.previous_segv);
	(void)sigaction(SIGBUS, &action, &st.previous_bus);
	st.handler_installed = true;
}

} // namespace

void user_map_initialize() noexcept
{
	auto &st = state();
	std::lock_guard lock{st.mutex};
	if (st.initialized)
		return;
	st.initialized = true;
	if (!env_flag_on("UML_JIT_USER_MAP"))
		return;
	if (!pick_and_reserve())
		return;
	st.enabled = true;
	install_handler();
}

bool user_map_enabled() noexcept
{
	return state().enabled;
}

std::uint64_t user_map_guest_base() noexcept
{
	return state().guest_base;
}

unsigned user_map_span_shift() noexcept
{
	return state().span_shift;
}

unsigned user_map_host_shift() noexcept
{
	auto page = state().host_page;
	unsigned shift = 0;
	while (page > 1U) {
		page >>= 1U;
		++shift;
	}
	return shift;
}

void user_map_bind(unsigned long generation, std::uint64_t &offset,
	const std::uint8_t *&bits) noexcept
{
	offset = 0;
	bits = nullptr;
	auto &st = state();
	if (!st.enabled || generation == 0)
		return;
	for (std::size_t index = 0; index < st.slot_count; ++index) {
		if (st.published_generation[index].load(
			    std::memory_order_acquire) != generation)
			continue;
		offset = st.slots[index].offset;
		bits = st.slots[index].bits.data();
		return;
	}
}

void user_map_sync_pages(unsigned long generation, std::uint64_t address,
	std::uint64_t length, void *host_source, int protection) noexcept
{
	if (host_source == nullptr)
		user_map_sync_unmap(generation, address, length);
	else
		apply_pages(generation, address, length, host_source, protection,
			true);
}

void user_map_sync_protect(unsigned long generation, std::uint64_t address,
	std::uint64_t length, int protection) noexcept
{
	auto &st = state();
	if (!st.enabled)
		return;
	std::lock_guard lock{st.mutex};
	auto *slot = slot_for_generation_locked(generation, false);
	if (slot == nullptr)
		return;
	for (std::uint64_t pos = 0; pos < length; pos += guest_page) {
		const auto found = slot->pages.find(address + pos);
		if (found != slot->pages.end())
			found->second.protection = protection;
	}
	refresh_span(*slot, address, length);
}

void user_map_sync_unmap(unsigned long generation, std::uint64_t address,
	std::uint64_t length) noexcept
{
	apply_pages(generation, address, length, nullptr, 0, false);
}

void user_map_clear_generation(unsigned long generation) noexcept
{
	auto &st = state();
	if (!st.enabled)
		return;
	std::lock_guard lock{st.mutex};
	const auto found = st.generation_slot.find(generation);
	if (found == st.generation_slot.end())
		return;
	const auto index = found->second;
	auto &slot = st.slots[index];
	st.published_generation[index].store(0, std::memory_order_release);
	reserve_exact(slot.host_base, st.span);
	std::fill(slot.bits.begin(), slot.bits.end(), 0);
	slot.pages.clear();
	slot.in_use = false;
	slot.generation = 0;
	st.generation_slot.erase(found);
}


void user_map_dump() noexcept
{
	auto &st = state();
	if (!st.initialized)
		return;
	std::lock_guard lock{st.mutex};
	dprintf(STDERR_FILENO,
		"UML_JIT_USER_MAP stats: enabled=%d slots=%zu assigned=%llu "
		"installs=%llu mixed_skips=%llu remap_failures=%llu unmaps=%llu "
		"live=%zu\n",
		st.enabled ? 1 : 0, st.slot_count,
		static_cast<unsigned long long>(st.slots_assigned),
		static_cast<unsigned long long>(st.installs),
		static_cast<unsigned long long>(st.mixed_skips),
		static_cast<unsigned long long>(st.remap_failures),
		static_cast<unsigned long long>(st.unmaps),
		st.generation_slot.size());
}

} // namespace uml::memory

extern "C" void uml_user_map_on_exit(void)
{
	::uml::memory::user_map_dump();
}
