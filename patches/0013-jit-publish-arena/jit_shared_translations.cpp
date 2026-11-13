// SPDX-License-Identifier: GPL-2.0-or-later
#include "jit_shared_translations.hpp"

#include "jit_linking.hpp"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <memory>
#include <limits>
#include <mutex>
#include <new>
#include <chrono>
#include <cstdlib>
#include <unistd.h>
#include <vector>

namespace uml::cpu::arm64 {

namespace {

constexpr std::size_t allocation_allowance = 64U;
constexpr auto maximum_size = std::numeric_limits<std::size_t>::max();

[[nodiscard]] constexpr std::size_t
saturating_add(std::size_t total, std::size_t bytes) noexcept {
  return bytes > maximum_size - total ? maximum_size : total + bytes;
}

[[nodiscard]] constexpr std::size_t
saturating_add_array(std::size_t total, std::size_t count,
                     std::size_t element_size) noexcept {
  if (total == maximum_size ||
      count > (maximum_size - total) / element_size)
    return maximum_size;
  return total + count * element_size;
}


/* A translation's identity in bytes, and in the 32-bit elements that hold
 * them: guest_word_count units of its ISA. For A64 and A32 these are
 * 4 * guest_word_count bytes and guest_word_count elements, as before. */
[[nodiscard]] std::size_t guest_identity_bytes(
    const SharedTranslation &translation) noexcept {
  return translation.guest_word_count *
         aarch32::isa_unit_bytes(
             static_cast<aarch32::GuestIsa>(translation.isa));
}

[[nodiscard]] std::size_t guest_identity_elements(
    const SharedTranslation &translation) noexcept {
  return (guest_identity_bytes(translation) + sizeof(std::uint32_t) - 1U) /
         sizeof(std::uint32_t);
}

[[nodiscard]] bool same_guest_words(
    const SharedTranslation &stored,
    std::span<const std::uint32_t> requested) noexcept {
  return stored.guest_words != nullptr &&
         guest_identity_elements(stored) == requested.size() &&
         std::memcmp(stored.guest_words.get(), requested.data(),
                     guest_identity_bytes(stored)) == 0;
}

[[nodiscard]] bool matches_guest_prefix(
    const SharedTranslation &stored,
    std::span<const std::uint32_t> requested) noexcept {
  return stored.guest_words != nullptr && stored.guest_word_count != 0 &&
         guest_identity_elements(stored) <= requested.size() &&
         std::memcmp(stored.guest_words.get(), requested.data(),
                     guest_identity_bytes(stored)) == 0;
}

/* Whether a translation's unit count is one its ISA can have: one unit per
 * instruction for A64 and A32, and for T32 one or two halfwords each. */
[[nodiscard]] bool valid_identity_units(
    const SharedTranslation &translation) noexcept {
  switch (static_cast<aarch32::GuestIsa>(translation.isa)) {
  case aarch32::GuestIsa::a64:
  case aarch32::GuestIsa::a32:
    return translation.guest_word_count == translation.guest_instructions &&
           translation.guest_word_count <= maximum_block_instructions;
  case aarch32::GuestIsa::t32:
    return translation.guest_instructions <= translation.guest_word_count &&
           translation.guest_word_count <= 2 * translation.guest_instructions &&
           translation.guest_instructions <= maximum_block_instructions;
  }
  return false;
}

[[nodiscard]] bool valid_shared_translation_shape(
    const SharedTranslation &translation,
    std::span<const std::uint32_t> requested) noexcept {
  if (translation.guest_words == nullptr ||
      translation.guest_word_count == 0 || translation.isa > 2U ||
      !valid_identity_units(translation) ||
      guest_identity_elements(translation) > requested.size() ||
      !matches_guest_prefix(translation, requested) ||
      translation.words.empty() || translation.hot_words == 0 ||
      translation.hot_words > translation.words.size() ||
      translation.internal_entry_word == 0 ||
      translation.internal_entry_word >= translation.hot_words ||
      !valid_link_state_metadata(translation.accesses_fp_state,
                                 translation.native_fp) ||
      (translation.direct_memory_write_mask &
       ~translation.memory_write_mask) != 0 ||
      translation.relocations.size() >
          maximum_shared_translation_relocations)
    return false;

  const auto guest_mask =
      translation.guest_instructions == maximum_block_instructions
          ? std::numeric_limits<std::uint64_t>::max()
          : (std::uint64_t{1} << translation.guest_instructions) - 1U;
  if ((translation.memory_write_mask & ~guest_mask) != 0)
    return false;

  for (std::size_t index = 0; index < translation.relocations.size();
       ++index) {
    const auto &relocation = translation.relocations[index];
    switch (relocation.kind) {
    case JitRelocationKind::direct_link:
    case JitRelocationKind::indirect_link:
    case JitRelocationKind::guest_pc:
      break;
    default:
      return false;
    }
    /* Relocations address aligned 64-bit literal-pool cells after executable
     * hot code. The shared template deliberately retains zero rather than a
     * publisher-local pointer; each executor resolves these neutral keys
     * against its private writable link records during installation. Never
     * permit a relocation to rewrite an instruction, straddle the end of the
     * retained words, or alias another relocation.
     */
    if ((relocation.word & 1U) != 0 ||
        relocation.word < translation.hot_words ||
        relocation.word >= translation.words.size() ||
        translation.words.size() - relocation.word < 2U ||
        translation.words[relocation.word] != 0 ||
        translation.words[relocation.word + 1U] != 0)
      return false;
    for (std::size_t earlier = 0; earlier < index; ++earlier) {
      const auto previous = translation.relocations[earlier].word;
      if (relocation.word == previous || relocation.word + 1U == previous ||
          previous + 1U == relocation.word)
        return false;
    }
  }
  return true;
}

[[nodiscard]] std::size_t
translation_payload_bytes(const SharedTranslation &translation) noexcept {
  auto total = saturating_add_array(0, translation.words.size(),
                                    sizeof(std::uint32_t));
  total = saturating_add_array(total, translation.relocations.size(),
                               sizeof(JitRelocation));
  return saturating_add_array(total, guest_identity_elements(translation),
                              sizeof(std::uint32_t));
}

/* Process-wide bump arena for packed SharedTranslation publications.
 * Each 1 MiB chunk is bump-allocated from a thread-local cursor (no lock
 * on the fast path). live counts publications that still occupy the chunk;
 * when the last one is evicted and the chunk is no longer a bump target,
 * the storage returns to a free list and is reused as a whole. Individual
 * publications are not freed back into the bump pointer.
 */
struct TranslationPublishChunk final {
  std::unique_ptr<std::byte[]> storage;
  std::size_t size{};
  std::atomic<std::size_t> bump{0};
  std::atomic<std::size_t> live{0};
  std::atomic<bool> retired{false};
};

class TranslationPublishArena final {
public:
  static constexpr std::size_t chunk_bytes = std::size_t{1} << 20;

  struct Allocation final {
    std::byte *ptr{};
    TranslationPublishChunk *chunk{};
    explicit operator bool() const noexcept { return ptr != nullptr; }
  };

  static TranslationPublishArena &instance() noexcept {
    static TranslationPublishArena arena;
    return arena;
  }

  [[nodiscard]] Allocation allocate(std::size_t bytes, std::size_t alignment) {
    if (alignment == 0)
      alignment = 1;
    const auto need = align_up(std::max(bytes, std::size_t{1}), alignment) +
                      alignment - 1U;
    thread_local TranslationPublishChunk *current = nullptr;
    if (current != nullptr) {
      if (auto got = try_bump(*current, bytes, alignment))
        return got;
      retire(current);
      current = nullptr;
    }
    current = take_chunk(std::max(need, chunk_bytes));
    if (auto got = try_bump(*current, bytes, alignment))
      return got;
    /* Oversized publications get a dedicated chunk. */
    retire(current);
    current = take_chunk(need);
    if (auto got = try_bump(*current, bytes, alignment))
      return got;
    throw std::bad_alloc();
  }

  static void release(TranslationPublishChunk *chunk) noexcept {
    if (chunk == nullptr)
      return;
    const auto previous = chunk->live.fetch_sub(1, std::memory_order_acq_rel);
    if (previous != 1)
      return;
    if (!chunk->retired.load(std::memory_order_acquire))
      return;
    instance().recycle(chunk);
  }

private:
  [[nodiscard]] static constexpr std::size_t align_up(std::size_t value,
                                                     std::size_t alignment) {
    return (value + alignment - 1U) & ~(alignment - 1U);
  }

  [[nodiscard]] static Allocation try_bump(TranslationPublishChunk &chunk,
                                           std::size_t bytes,
                                           std::size_t alignment) noexcept {
    auto offset = chunk.bump.load(std::memory_order_relaxed);
    for (;;) {
      const auto aligned = align_up(offset, alignment);
      const auto needed = align_up(std::max(bytes, std::size_t{1}), alignment);
      if (aligned > chunk.size || needed > chunk.size - aligned)
        return {};
      if (chunk.bump.compare_exchange_weak(offset, aligned + needed,
                                           std::memory_order_release,
                                           std::memory_order_relaxed)) {
        chunk.live.fetch_add(1, std::memory_order_relaxed);
        return {chunk.storage.get() + aligned, &chunk};
      }
    }
  }

  [[nodiscard]] TranslationPublishChunk *take_chunk(std::size_t size) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!freelist_.empty() && freelist_.back()->size >= size) {
      auto *chunk = freelist_.back();
      freelist_.pop_back();
      chunk->bump.store(0, std::memory_order_relaxed);
      chunk->live.store(0, std::memory_order_relaxed);
      chunk->retired.store(false, std::memory_order_relaxed);
      return chunk;
    }
    auto chunk = std::make_unique<TranslationPublishChunk>();
    const auto bytes = std::max(size, chunk_bytes);
    chunk->storage = std::make_unique<std::byte[]>(bytes);
    chunk->size = bytes;
    auto *raw = chunk.get();
    owned_.push_back(std::move(chunk));
    return raw;
  }

  void retire(TranslationPublishChunk *chunk) noexcept {
    if (chunk == nullptr)
      return;
    chunk->retired.store(true, std::memory_order_release);
    if (chunk->live.load(std::memory_order_acquire) == 0)
      recycle(chunk);
  }

  void recycle(TranslationPublishChunk *chunk) noexcept {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!chunk->retired.load(std::memory_order_acquire) ||
        chunk->live.load(std::memory_order_acquire) != 0)
      return;
    for (auto *existing : freelist_) {
      if (existing == chunk)
        return;
    }
    chunk->bump.store(0, std::memory_order_relaxed);
    freelist_.push_back(chunk);
  }

  std::mutex mutex_;
  std::vector<std::unique_ptr<TranslationPublishChunk>> owned_;
  std::vector<TranslationPublishChunk *> freelist_;
};

} // namespace

std::shared_ptr<SharedTranslation> make_packed_shared_translation(
    std::span<const std::uint32_t> host_words,
    std::span<const JitRelocation> relocations,
    std::span<const std::uint32_t> guest_words) {
  const auto align_to = [](std::size_t value, std::size_t alignment) {
    return (value + alignment - 1U) & ~(alignment - 1U);
  };
  const auto guest_bytes = guest_words.size() * sizeof(std::uint32_t);
  const auto host_bytes = host_words.size() * sizeof(std::uint32_t);
  const auto reloc_bytes = relocations.size() * sizeof(JitRelocation);
  const auto object_bytes =
      align_to(sizeof(SharedTranslation), alignof(SharedTranslation));
  const auto guest_off = object_bytes;
  const auto host_off =
      align_to(guest_off + guest_bytes, alignof(std::uint32_t));
  const auto reloc_off =
      align_to(host_off + host_bytes, alignof(JitRelocation));
  const auto total = std::max(reloc_off + reloc_bytes, object_bytes + 1U);
  auto allocation = TranslationPublishArena::instance().allocate(
      total, alignof(SharedTranslation));
  auto *base = allocation.ptr;
  auto *object = reinterpret_cast<SharedTranslation *>(base);
  auto *guest = reinterpret_cast<std::uint32_t *>(base + guest_off);
  auto *host = reinterpret_cast<std::uint32_t *>(base + host_off);
  auto *reloc = reinterpret_cast<JitRelocation *>(base + reloc_off);
  if (!guest_words.empty())
    std::memcpy(guest, guest_words.data(), guest_bytes);
  if (!host_words.empty())
    std::memcpy(host, host_words.data(), host_bytes);
  if (!relocations.empty())
    std::memcpy(reloc, relocations.data(), reloc_bytes);
  for (std::size_t index = 0; index < relocations.size(); ++index) {
    const auto word = reloc[index].word;
    if (word + 1U < host_words.size()) {
      host[word] = 0;
      host[word + 1U] = 0;
    }
  }
  /* One arena block holds the object and the packed payload. The returned
   * shared_ptr and guest_words share a single control block whose deleter
   * destroys the object and drops the chunk's live count. */
  ::new (object) SharedTranslation();
  auto owner = std::shared_ptr<std::byte>(
      base, [chunk = allocation.chunk, object](std::byte *) noexcept {
        object->~SharedTranslation();
        TranslationPublishArena::release(chunk);
      });
  auto translation = std::shared_ptr<SharedTranslation>(owner, object);
  translation->words = std::span<std::uint32_t>{host, host_words.size()};
  translation->relocations =
      std::span<JitRelocation>{reloc, relocations.size()};
  translation->guest_words =
      std::shared_ptr<const std::uint32_t[]>{owner, guest};
  return translation;
}


bool valid_shared_translation(
    const SharedTranslation &translation,
    std::span<const std::uint32_t> requested) noexcept {
  return translation.direct_link_refusals == 0 &&
         translation.indirect_link_refusals == 0 &&
         valid_shared_translation_shape(translation, requested);
}

SharedTranslationCache::SharedTranslationCache(
    std::size_t shard_capacity,
    std::size_t maximum_accounted_bytes) noexcept
    : accounted_bytes_{minimum_shared_translation_cache_bytes},
      shard_capacity_{shard_capacity},
      maximum_accounted_bytes_{std::max(
          maximum_accounted_bytes,
          minimum_shared_translation_cache_bytes)} {
  /* Pre-size the location index so cold publication does not rehash the
   * map while the first gcc / libxul compile is filling it. */
  locations_.reserve(1U << 18);
}

SharedTranslationCache::~SharedTranslationCache() {
  for (auto &slot : shards_)
    delete slot.shard.load(std::memory_order_relaxed);
}

static_assert(sizeof(SharedTranslationCache) + allocation_allowance <=
              minimum_shared_translation_cache_bytes);

bool SharedTranslationCache::CodegenProfile::operator==(
    const CodegenProfile &other) const noexcept {
  return capabilities == other.capabilities &&
         translation_mode == other.translation_mode;
}

SharedTranslationCache::Shard *SharedTranslationCache::allocated_shard(
    std::uint64_t guest_pc) const noexcept {
  return shards_[shard_of(guest_pc)].shard.load(std::memory_order_acquire);
}

SharedTranslationCache::Shard &SharedTranslationCache::ensure_shard(
    std::uint64_t guest_pc) {
  auto &slot = shards_[shard_of(guest_pc)];
  if (auto *shard = slot.shard.load(std::memory_order_acquire);
      shard != nullptr)
    return *shard;
  const std::lock_guard creation_lock{slot.creation_mutex};
  if (auto *shard = slot.shard.load(std::memory_order_relaxed);
      shard != nullptr)
    return *shard;
  auto shard = std::make_unique<Shard>();
  shard->entries.reserve(32768);
  auto *result = shard.release();
  slot.shard.store(result, std::memory_order_release);
  return *result;
}

void SharedTranslationCache::index_location(const Entry &entry) {
  if (entry.translation == nullptr ||
      entry.translation->code_page_identity == 0)
    return;
  const auto key = location_key(entry.translation->code_page_identity,
                                entry.translation->code_page_version,
                                entry.translation->recorded_pc);
  const std::unique_lock lock{locations_mutex_};
  locations_[key].push_back(entry);
}

void SharedTranslationCache::drop_location(const Entry &entry) noexcept {
  if (entry.translation == nullptr ||
      entry.translation->code_page_identity == 0)
    return;
  const auto key = location_key(entry.translation->code_page_identity,
                                entry.translation->code_page_version,
                                entry.translation->recorded_pc);
  const std::unique_lock lock{locations_mutex_};
  const auto found = locations_.find(key);
  if (found == locations_.end())
    return;
  auto &bucket = found->second;
  bucket.erase(std::remove_if(bucket.begin(), bucket.end(),
                              [&](const Entry &candidate) {
                                return candidate.translation ==
                                       entry.translation;
                              }),
               bucket.end());
  if (bucket.empty())
    locations_.erase(found);
}


namespace {

[[nodiscard]] bool shared_stats_enabled() noexcept {
  static const bool enabled = [] {
    const char *value = std::getenv("UML_JIT_SHARED_STATS");
    return value != nullptr && value[0] != '\0' && value[0] != '0';
  }();
  return enabled;
}

std::atomic<std::uint64_t> same_va_matches_{};
std::atomic<std::uint64_t> location_matches_{};
std::atomic<std::uint64_t> slide_hits_{};
std::atomic<std::uint64_t> identity_zero_finds_{};
std::atomic<std::uint64_t> identity_nonzero_finds_{};
std::atomic<std::uint64_t> last_dump_ns_{};
std::atomic<bool> stats_hook_installed_{false};

void dump_shared_translation_stats(const char *why) noexcept {
  const auto stats = SharedTranslationCache::instance().statistics();
  dprintf(STDERR_FILENO,
          "===JIT_SHARED_STATS=== why=%s matches=%llu same_va=%llu "
          "location=%llu slide=%llu reuses=%llu misses=%llu insertions=%llu "
          "evictions=%llu rejected=%llu degraded=%llu malformed=%llu "
          "ins_fail=%llu mat_meta=%llu mat_direct=%llu mat_indirect=%llu "
          "mat_arena=%llu entries=%llu payload=%llu accounted=%llu max=%llu "
          "id0=%llu idN=%llu\n",
          why,
          static_cast<unsigned long long>(stats.matches),
          static_cast<unsigned long long>(
              same_va_matches_.load(std::memory_order_relaxed)),
          static_cast<unsigned long long>(
              location_matches_.load(std::memory_order_relaxed)),
          static_cast<unsigned long long>(
              slide_hits_.load(std::memory_order_relaxed)),
          static_cast<unsigned long long>(stats.reuses),
          static_cast<unsigned long long>(stats.misses),
          static_cast<unsigned long long>(stats.insertions),
          static_cast<unsigned long long>(stats.evictions),
          static_cast<unsigned long long>(stats.rejected),
          static_cast<unsigned long long>(stats.degraded_rejected),
          static_cast<unsigned long long>(stats.malformed_rejected),
          static_cast<unsigned long long>(stats.insertion_failures),
          static_cast<unsigned long long>(
              stats.materialization_invalid_metadata_failures),
          static_cast<unsigned long long>(
              stats.materialization_direct_link_failures),
          static_cast<unsigned long long>(
              stats.materialization_indirect_link_failures),
          static_cast<unsigned long long>(
              stats.materialization_arena_failures),
          static_cast<unsigned long long>(stats.entries),
          static_cast<unsigned long long>(stats.payload_bytes),
          static_cast<unsigned long long>(stats.accounted_bytes),
          static_cast<unsigned long long>(stats.maximum_accounted_bytes),
          static_cast<unsigned long long>(
              identity_zero_finds_.load(std::memory_order_relaxed)),
          static_cast<unsigned long long>(
              identity_nonzero_finds_.load(std::memory_order_relaxed)));
}

void maybe_dump_shared_translation_stats() noexcept {
  if (!shared_stats_enabled())
    return;
  const auto now = static_cast<std::uint64_t>(
      std::chrono::duration_cast<std::chrono::nanoseconds>(
          std::chrono::steady_clock::now().time_since_epoch())
          .count());
  auto last = last_dump_ns_.load(std::memory_order_relaxed);
  if (last != 0 && now - last < 1'000'000'000ULL)
    return;
  if (!last_dump_ns_.compare_exchange_strong(last, now,
                                             std::memory_order_relaxed))
    return;
  dump_shared_translation_stats("periodic");
}

void install_shared_stats_hook() noexcept {
  if (!shared_stats_enabled())
    return;
  bool expected = false;
  if (!stats_hook_installed_.compare_exchange_strong(
          expected, true, std::memory_order_relaxed))
    return;
  std::atexit([] { dump_shared_translation_stats("atexit"); });
}

} // namespace

std::shared_ptr<const SharedTranslation>
SharedTranslationCache::find_at_location(
    const CodegenProfile &profile, std::uint64_t guest_pc,
    std::span<const std::uint32_t> guest_words, std::uint64_t identity,
    std::uint64_t version) const {
  if (identity == 0)
    return nullptr;
  const auto key = location_key(identity, version, guest_pc);
  const std::shared_lock lock{locations_mutex_};
  const auto found = locations_.find(key);
  if (found == locations_.end())
    return nullptr;
  for (const auto &entry : found->second)
    if (entry.profile == profile &&
        matches_guest_prefix(*entry.translation, guest_words))
      return entry.translation;
  return nullptr;
}

std::shared_ptr<const SharedTranslation> SharedTranslationCache::find(
    const CodegenProfile &profile, std::uint64_t guest_pc,
    std::span<const std::uint32_t> guest_words) const {
  return find(profile, guest_pc, guest_words, 0, 0);
}

std::shared_ptr<const SharedTranslation> SharedTranslationCache::find(
    const CodegenProfile &profile, std::uint64_t guest_pc,
    std::span<const std::uint32_t> guest_words,
    std::uint64_t code_page_identity, std::uint64_t code_page_version) const {
  if (const auto *shard = allocated_shard(guest_pc); shard != nullptr) {
    const std::shared_lock cache_lock{shard->mutex};
    const auto bucket = shard->entries.find(guest_pc);
    if (bucket != shard->entries.end())
      for (const auto &entry : bucket->second)
        if (entry.profile == profile &&
            matches_guest_prefix(*entry.translation, guest_words)) {
          matches_.fetch_add(1, std::memory_order_relaxed);
          same_va_matches_.fetch_add(1, std::memory_order_relaxed);
          maybe_dump_shared_translation_stats();
          return entry.translation;
        }
  }
  if (code_page_identity == 0)
    identity_zero_finds_.fetch_add(1, std::memory_order_relaxed);
  else
    identity_nonzero_finds_.fetch_add(1, std::memory_order_relaxed);
  if (auto located = find_at_location(profile, guest_pc, guest_words,
                                      code_page_identity,
                                      code_page_version);
      located != nullptr) {
    matches_.fetch_add(1, std::memory_order_relaxed);
    location_matches_.fetch_add(1, std::memory_order_relaxed);
    if (located->recorded_pc != guest_pc)
      slide_hits_.fetch_add(1, std::memory_order_relaxed);
    maybe_dump_shared_translation_stats();
    return located;
  }
  misses_.fetch_add(1, std::memory_order_relaxed);
  maybe_dump_shared_translation_stats();
  return nullptr;
}

SharedTranslationPublicationPreflight
SharedTranslationCache::preflight_publication(
    const CodegenProfile &profile, std::uint64_t guest_pc,
    std::span<const std::uint32_t> guest_words,
    SharedTranslationPublicationSizes sizes,
    std::size_t direct_link_refusals,
    std::size_t indirect_link_refusals,
    std::uint64_t code_page_identity,
    std::uint64_t code_page_version) {
  auto *shard = allocated_shard(guest_pc);
  std::shared_lock<std::shared_mutex> cache_lock;
  if (shard != nullptr) {
    cache_lock = std::shared_lock{shard->mutex};
    const auto found = shard->entries.find(guest_pc);
    if (found != shard->entries.end())
      for (const auto &entry : found->second)
        if (entry.profile == profile &&
            same_guest_words(*entry.translation, guest_words))
          return {.canonical = entry.translation, .may_construct = false};
  }
  if (auto located = find_at_location(profile, guest_pc, guest_words,
                                      code_page_identity, code_page_version);
      located != nullptr)
    return {.canonical = located, .may_construct = false};

  /* Existing ownership remains useful after its publisher exits. A single
   * live executor may also admit a new owner so a later exec can reuse it.
   */
  if (live_executors_.load(std::memory_order_relaxed) < 1U)
    return {};

  /* A compiler may have lost stable-link capacity while another executor
   * published the same complete translation. Prefer that raced canonical
   * owner above; otherwise record one event for the degraded compilation and
   * leave the key available to a later full translation.
   */
  if (refuse_degraded_publication(direct_link_refusals,
                                  indirect_link_refusals))
    return {};

  /* The guest span is the exact validation prefix. Do not let an inconsistent
   * advisory count underestimate it; insert() still validates the completed
   * candidate and charges actual vector capacities.
   */
  sizes.guest_words = std::max(sizes.guest_words, guest_words.size());
  const auto lower_bound = lower_bound_entry_budget_charge(sizes);
  if (shard != nullptr &&
      (shard->count >= shard_capacity_ ||
       !budget_can_fit(additional_budget_charge(*shard, lower_bound)))) {
    cache_lock.unlock();
    std::unique_lock reclaim_lock{shard->mutex};
    reclaim_unused(*shard, lower_bound);
    if (shard->count < shard_capacity_ &&
        budget_can_fit(additional_budget_charge(*shard, lower_bound)))
      return {.canonical = nullptr, .may_construct = true};
    reclaim_lock.unlock();
    reclaim_other_shards(shard, lower_bound);
    if (budget_can_fit(lower_bound))
      return {.canonical = nullptr, .may_construct = true};
    rejected_.fetch_add(1, std::memory_order_relaxed);
    return {};
  }
  if ((shard != nullptr && shard->count >= shard_capacity_) ||
      !budget_can_fit(shard == nullptr ? lower_bound :
                     additional_budget_charge(*shard, lower_bound))) {
    reclaim_other_shards(shard, lower_bound);
    if (budget_can_fit(lower_bound) &&
        (shard == nullptr || shard->count < shard_capacity_))
      return {.canonical = nullptr, .may_construct = true};
    rejected_.fetch_add(1, std::memory_order_relaxed);
    return {};
  }
  return {.canonical = nullptr, .may_construct = true};
}

std::shared_ptr<const SharedTranslation> SharedTranslationCache::insert(
    const CodegenProfile &profile, std::uint64_t guest_pc,
    std::span<const std::uint32_t> guest_words,
    std::shared_ptr<const SharedTranslation> translation) {
  const auto record_malformed = [&](std::size_t reason) {
    malformed_rejected_.fetch_add(1, std::memory_order_relaxed);
    if (reason < malformed_reason_count)
      malformed_reasons_[reason].fetch_add(1, std::memory_order_relaxed);
  };
  if (translation == nullptr) {
    record_malformed(0);
    return nullptr;
  }
  if (translation->guest_words == nullptr ||
      translation->guest_word_count == 0 || translation->isa > 2U) {
    record_malformed(1);
    return nullptr;
  }
  if (!valid_identity_units(*translation)) {
    record_malformed(2);
    return nullptr;
  }
  if (guest_identity_elements(*translation) != guest_words.size() ||
      !matches_guest_prefix(*translation, guest_words)) {
    record_malformed(3);
    return nullptr;
  }
  if (translation->words.empty() || translation->hot_words == 0 ||
      translation->hot_words > translation->words.size()) {
    record_malformed(4);
    return nullptr;
  }
  if (translation->internal_entry_word == 0 ||
      translation->internal_entry_word >= translation->hot_words) {
    record_malformed(5);
    return nullptr;
  }
  if (!valid_link_state_metadata(translation->accesses_fp_state,
                                 translation->native_fp)) {
    record_malformed(6);
    return nullptr;
  }
  if ((translation->direct_memory_write_mask &
       ~translation->memory_write_mask) != 0) {
    record_malformed(7);
    return nullptr;
  }
  if (translation->relocations.size() >
      maximum_shared_translation_relocations) {
    record_malformed(8);
    return nullptr;
  }
  const auto guest_mask =
      translation->guest_instructions == maximum_block_instructions
          ? std::numeric_limits<std::uint64_t>::max()
          : (std::uint64_t{1} << translation->guest_instructions) - 1U;
  if ((translation->memory_write_mask & ~guest_mask) != 0) {
    record_malformed(9);
    return nullptr;
  }
  for (std::size_t index = 0; index < translation->relocations.size();
       ++index) {
    const auto &relocation = translation->relocations[index];
    switch (relocation.kind) {
    case JitRelocationKind::direct_link:
    case JitRelocationKind::indirect_link:
    case JitRelocationKind::guest_pc:
      break;
    default:
      record_malformed(10);
      return nullptr;
    }
    if ((relocation.word & 1U) != 0 ||
        relocation.word < translation->hot_words ||
        relocation.word >= translation->words.size() ||
        translation->words.size() - relocation.word < 2U) {
      record_malformed(11);
      return nullptr;
    }
    if (translation->words[relocation.word] != 0 ||
        translation->words[relocation.word + 1U] != 0) {
      record_malformed(12);
      return nullptr;
    }
    for (std::size_t earlier = 0; earlier < index; ++earlier) {
      const auto previous = translation->relocations[earlier].word;
      if (relocation.word == previous || relocation.word + 1U == previous ||
          previous + 1U == relocation.word) {
        record_malformed(13);
        return nullptr;
      }
    }
  }
  if (static_cast<aarch32::GuestIsa>(translation->isa) !=
      aarch32::key_isa(guest_pc)) {
    record_malformed(14);
    return nullptr;
  }
  /* The checks above are exactly valid_shared_translation_shape(); a second
   * walk and memcmp would only repeat them (6% of compile-cold SIGPROF). */
  auto &shard = ensure_shard(guest_pc);
  std::unique_lock cache_lock{shard.mutex};
  const auto found = shard.entries.find(guest_pc);
  if (found != shard.entries.end())
    for (const auto &entry : found->second)
      if (entry.profile == profile &&
          same_guest_words(*entry.translation, guest_words))
        return entry.translation;
  if (auto located = find_at_location(profile, guest_pc, guest_words,
                                      translation->code_page_identity,
                                      translation->code_page_version);
      located != nullptr)
    return located;
  /* A single live executor may admit a new owner. Publication stops only
   * when no executor remains (tests, or a drained pool).
   */
  if (live_executors_.load(std::memory_order_relaxed) < 1U)
    return nullptr;
  /* A racing canonical entry above is reusable even when this caller's
   * private compilation was degraded. Otherwise leave the key unoccupied so
   * an executor with direct-link capacity can publish a full translation
   * later.
   */
  if (refuse_degraded_publication(translation->direct_link_refusals,
                                  translation->indirect_link_refusals))
    return nullptr;
  const auto payload_bytes = translation_payload_bytes(*translation);
  const auto budget_charge = entry_budget_charge(*translation);
  reclaim_unused(shard, budget_charge);
  auto additional_charge = additional_budget_charge(shard, budget_charge);
  if (shard.count >= shard_capacity_ || !budget_can_fit(additional_charge)) {
    cache_lock.unlock();
    reclaim_other_shards(&shard, budget_charge);
    cache_lock.lock();
    reclaim_unused(shard, budget_charge);
    additional_charge = additional_budget_charge(shard, budget_charge);
  }
  if (shard.count >= shard_capacity_ || !reserve_budget(additional_charge)) {
    rejected_.fetch_add(1, std::memory_order_relaxed);
    return nullptr;
  }
  bool retain_reservation_on_failure = false;
  try {
    auto [bucket, inserted] = shard.entries.try_emplace(guest_pc);
    try {
      bucket->second.push_back({profile, translation});
      index_location(bucket->second.back());
    } catch (...) {
      if (inserted) {
        shard.entries.erase(bucket);
        /* A successful map insertion may have enlarged the shard's bucket
         * array. erase() removes the node but does not promise to shrink that
         * retained allocation, so keep the conservative reservation rather
         * than letting an allocation-failure path escape the global cap.
         */
        retain_reservation_on_failure = true;
      }
      throw;
    }
  } catch (...) {
    insertion_failures_.fetch_add(1, std::memory_order_relaxed);
    if (!retain_reservation_on_failure) {
      release_budget(additional_charge);
    } else {
      failed_insertion_retained_accounted_bytes_.fetch_add(
          additional_charge, std::memory_order_relaxed);
    }
    throw;
  }
  shard.index_credit -= budget_charge - additional_charge;
  ++shard.count;
  payload_bytes_.fetch_add(payload_bytes, std::memory_order_relaxed);
  insertions_.fetch_add(1, std::memory_order_relaxed);
  return translation;
}

std::size_t SharedTranslationCache::entry_budget_charge(
    const SharedTranslation &translation) const noexcept {
  return entry_budget_charge_from_payload(
      translation_payload_bytes(translation));
}

std::size_t SharedTranslationCache::lower_bound_entry_budget_charge(
    SharedTranslationPublicationSizes sizes) noexcept {
  auto payload = saturating_add_array(
      0, sizes.host_words, sizeof(std::uint32_t));
  payload = saturating_add_array(payload, sizes.relocations,
                                 sizeof(JitRelocation));
  payload = saturating_add_array(payload, sizes.guest_words,
                                 sizeof(std::uint32_t));
  return entry_budget_charge_from_payload(payload);
}

std::size_t SharedTranslationCache::entry_budget_charge_from_payload(
    std::size_t payload_bytes) noexcept {
  auto total = payload_bytes;
  /* Charge the translation/control allocation, worst-case 2x vector backing
   * for Entry growth, a complete map node/value, and a deliberately generous
   * sixteen bucket pointers per entry. The cache's fixed 64 KiB base charge
   * separately absorbs its 64 empty shards and first-bucket effects. Eight
   * allocator allowances cover the translation, its three payload buffers,
   * entry storage, node storage, bucket storage, and shared ownership control.
   * Entries sharing a PC still pay every charge, so the retained accounting
   * intentionally dominates the actual sharded-map allocation.
   */
  total = saturating_add(total, sizeof(SharedTranslation));
  total = saturating_add(total, 2U * sizeof(Entry));
  total = saturating_add(
      total, sizeof(std::uint64_t) + sizeof(std::vector<Entry>));
  total = saturating_add(total, 16U * sizeof(void *));
  total = saturating_add(total, 8U * allocation_allowance);
  return total;
}

std::size_t SharedTranslationCache::entry_index_budget_charge() noexcept {
  return 2U * sizeof(Entry) + sizeof(std::uint64_t) +
         sizeof(std::vector<Entry>) + 16U * sizeof(void *) +
         3U * allocation_allowance;
}

std::size_t SharedTranslationCache::additional_budget_charge(
    const Shard &shard, std::size_t charge) noexcept {
  if (charge == maximum_size)
    return charge;
  return charge - std::min(shard.index_credit, entry_index_budget_charge());
}

void SharedTranslationCache::reclaim_unused(
    Shard &shard, std::size_t charge) noexcept {
  if (charge == maximum_size ||
      (shard.count < shard_capacity_ &&
       budget_can_fit(additional_budget_charge(shard, charge))))
    return;
  /* Keep the map's high-water index reservation after erasing nodes: its
   * bucket array may survive. New entries reuse that credit, so replacement
   * neither undercounts retained buckets nor accumulates a fresh index charge
   * for each generation of the working set.
   *
   * Resume a bounded sweep by key, not by an iterator that insertion can
   * invalidate. Private validation words and materializing translations pin
   * their retained storage. Callers acquire strong ownership under this
   * shard's lock; they must not resurrect owners through weak pointers.
   */
  auto victim = shard.victim_initialized ?
      shard.entries.find(shard.next_victim) : shard.entries.end();
  if (victim == shard.entries.end())
    victim = shard.entries.begin();
  const auto attempts = std::min<std::size_t>(shard.entries.size(), 256U);
  for (std::size_t attempt = 0;
       attempt < attempts && victim != shard.entries.end(); ++attempt) {
    const bool unused = std::ranges::all_of(victim->second,
        [](const Entry &entry) {
          /* The SharedTranslation object and packed payload share one
           * arena control block. The cache entry holds one reference and
           * the object's guest_words member holds the other, so a uniquely
           * cached publication has use_count 2. An L1 pin of either pointer
           * raises both counts together. */
          const auto uses = entry.translation.use_count();
          return uses == 2 &&
                 entry.translation->guest_words.use_count() == uses;
        });
    if (unused) {
      std::size_t released = 0;
      std::size_t payload = 0;
      for (const auto &entry : victim->second) {
        released += entry_budget_charge(*entry.translation) -
                    entry_index_budget_charge();
        payload += translation_payload_bytes(*entry.translation);
      }
      const auto count = victim->second.size();
      for (const auto &entry : victim->second)
        drop_location(entry);
      victim = shard.entries.erase(victim);
      shard.count -= count;
      shard.index_credit += count * entry_index_budget_charge();
      payload_bytes_.fetch_sub(payload, std::memory_order_relaxed);
      evictions_.fetch_add(count, std::memory_order_relaxed);
      release_budget(released);
    } else {
      ++victim;
    }
    if (victim == shard.entries.end())
      victim = shard.entries.begin();
    if (shard.count < shard_capacity_ &&
        budget_can_fit(additional_budget_charge(shard, charge)))
      break;
  }
  /* Unused owners were pinned by every live L1. Evict anyway so a later
   * process can publish new blocks; materialized copies stay in those L1s.
   */
  if (!(shard.count < shard_capacity_ &&
        budget_can_fit(additional_budget_charge(shard, charge))) &&
      !shard.entries.empty()) {
    if (victim == shard.entries.end())
      victim = shard.entries.begin();
    const auto start_key = victim->first;
    bool wrapped = false;
    while (victim != shard.entries.end() &&
           !(shard.count < shard_capacity_ &&
             budget_can_fit(additional_budget_charge(shard, charge)))) {
      if (wrapped && victim->first == start_key)
        break;
      std::size_t released = 0;
      std::size_t payload = 0;
      for (const auto &entry : victim->second) {
        released += entry_budget_charge(*entry.translation) -
                    entry_index_budget_charge();
        payload += translation_payload_bytes(*entry.translation);
      }
      const auto count = victim->second.size();
      for (const auto &entry : victim->second)
        drop_location(entry);
      victim = shard.entries.erase(victim);
      shard.count -= count;
      shard.index_credit += count * entry_index_budget_charge();
      payload_bytes_.fetch_sub(payload, std::memory_order_relaxed);
      evictions_.fetch_add(count, std::memory_order_relaxed);
      release_budget(released);
      if (victim == shard.entries.end()) {
        victim = shard.entries.begin();
        wrapped = true;
        if (victim == shard.entries.end())
          break;
      }
    }
  }
  shard.victim_initialized = victim != shard.entries.end();
  if (shard.victim_initialized)
    shard.next_victim = victim->first;
}


void SharedTranslationCache::reclaim_other_shards(const Shard *except,
                                                 std::size_t charge) noexcept {
  if (charge == maximum_size || budget_can_fit(charge))
    return;
  for (auto &slot : shards_) {
    auto *shard = slot.shard.load(std::memory_order_acquire);
    if (shard == nullptr || shard == except)
      continue;
    {
      const std::unique_lock lock{shard->mutex};
      reclaim_unused(*shard, charge);
    }
    if (budget_can_fit(charge))
      return;
  }
}

bool SharedTranslationCache::budget_can_fit(std::size_t bytes) const noexcept {
  if (bytes == maximum_size)
    return false;
  const auto current = accounted_bytes_.load(std::memory_order_relaxed);
  return current <= maximum_accounted_bytes_ &&
         bytes <= maximum_accounted_bytes_ - current;
}

bool SharedTranslationCache::reserve_budget(std::size_t bytes) noexcept {
  if (bytes == maximum_size)
    return false;
  auto current = accounted_bytes_.load(std::memory_order_relaxed);
  for (;;) {
    if (current > maximum_accounted_bytes_ ||
        bytes > maximum_accounted_bytes_ - current)
      return false;
    if (accounted_bytes_.compare_exchange_weak(
            current, current + bytes, std::memory_order_relaxed,
            std::memory_order_relaxed))
      return true;
  }
}

void SharedTranslationCache::release_budget(std::size_t bytes) noexcept {
  accounted_bytes_.fetch_sub(bytes, std::memory_order_relaxed);
}

bool SharedTranslationCache::accepts_publications() const noexcept {
  return live_executors_.load(std::memory_order_relaxed) >= 1U;
}

bool SharedTranslationCache::refuse_degraded_publication(
    std::size_t direct_link_refusals,
    std::size_t indirect_link_refusals) noexcept {
  if (direct_link_refusals == 0 && indirect_link_refusals == 0)
    return false;
  degraded_rejected_.fetch_add(1, std::memory_order_relaxed);
  return true;
}

void SharedTranslationCache::record_reuse() noexcept {
  reuses_.fetch_add(1, std::memory_order_relaxed);
}

void SharedTranslationCache::record_materialization_failure(
    SharedTranslationMaterializationFailure failure) noexcept {
  switch (failure) {
  case SharedTranslationMaterializationFailure::invalid_metadata:
    materialization_invalid_metadata_failures_.fetch_add(
        1, std::memory_order_relaxed);
    break;
  case SharedTranslationMaterializationFailure::direct_link_capacity:
    materialization_direct_link_failures_.fetch_add(
        1, std::memory_order_relaxed);
    break;
  case SharedTranslationMaterializationFailure::indirect_link_capacity:
    materialization_indirect_link_failures_.fetch_add(
        1, std::memory_order_relaxed);
    break;
  case SharedTranslationMaterializationFailure::arena_exhaustion:
    materialization_arena_failures_.fetch_add(1,
                                              std::memory_order_relaxed);
    break;
  }
}

void SharedTranslationCache::add_executor() noexcept {
  live_executors_.fetch_add(1, std::memory_order_relaxed);
}

void SharedTranslationCache::remove_executor() noexcept {
  live_executors_.fetch_sub(1, std::memory_order_relaxed);
}

SharedTranslationStatistics
SharedTranslationCache::statistics() const noexcept {
  std::size_t entries = 0;
  for (const auto &slot : shards_) {
    const auto *shard = slot.shard.load(std::memory_order_acquire);
    if (shard == nullptr)
      continue;
    const std::shared_lock cache_lock{shard->mutex};
    entries += shard->count;
  }
  return {.matches = matches_.load(std::memory_order_relaxed),
          .reuses = reuses_.load(std::memory_order_relaxed),
          .misses = misses_.load(std::memory_order_relaxed),
          .insertions = insertions_.load(std::memory_order_relaxed),
          .evictions = evictions_.load(std::memory_order_relaxed),
          .rejected = rejected_.load(std::memory_order_relaxed),
          .degraded_rejected =
              degraded_rejected_.load(std::memory_order_relaxed),
          .malformed_rejected =
              malformed_rejected_.load(std::memory_order_relaxed),
          .insertion_failures =
              insertion_failures_.load(std::memory_order_relaxed),
          .failed_insertion_retained_accounted_bytes =
              failed_insertion_retained_accounted_bytes_.load(
                  std::memory_order_relaxed),
          .materialization_invalid_metadata_failures =
              materialization_invalid_metadata_failures_.load(
                  std::memory_order_relaxed),
          .materialization_direct_link_failures =
              materialization_direct_link_failures_.load(
                  std::memory_order_relaxed),
          .materialization_indirect_link_failures =
              materialization_indirect_link_failures_.load(
                  std::memory_order_relaxed),
          .materialization_arena_failures =
              materialization_arena_failures_.load(
                  std::memory_order_relaxed),
          .entries = entries,
          .payload_bytes = payload_bytes_.load(std::memory_order_relaxed),
          .accounted_bytes =
              accounted_bytes_.load(std::memory_order_relaxed),
          .maximum_accounted_bytes = maximum_accounted_bytes_};
}

std::array<std::uint64_t, SharedTranslationCache::malformed_reason_count>
SharedTranslationCache::malformed_reasons() const noexcept {
  std::array<std::uint64_t, malformed_reason_count> counts{};
  for (std::size_t index = 0; index < malformed_reason_count; ++index)
    counts[index] = malformed_reasons_[index].load(std::memory_order_relaxed);
  return counts;
}

std::size_t SharedTranslationCache::allocated_shards() const noexcept {
  return std::ranges::count_if(shards_, [](const auto &slot) {
    return slot.shard.load(std::memory_order_acquire) != nullptr;
  });
}

SharedTranslationCache &SharedTranslationCache::instance() noexcept {
  /* Intentionally leaked. Executors flush into it from their destructors,
   * which can run after a function-local static would have been destroyed.
   */
  static auto *cache = new SharedTranslationCache{
      unlimited_shard_entries,
      jit_shared_translation_cache_budget()};
  install_shared_stats_hook();
  return *cache;
}

} // namespace uml::cpu::arm64
