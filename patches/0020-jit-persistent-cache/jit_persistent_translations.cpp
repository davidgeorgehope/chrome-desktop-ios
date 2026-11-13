// SPDX-License-Identifier: GPL-2.0-or-later
#include "jit_persistent_translations.hpp"

#include "jit_runtime_contract.hpp"

#include <algorithm>
#include <atomic>
#include <array>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <mutex>
#include <optional>
#include <span>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <unordered_map>
#include <vector>

namespace uml::cpu::arm64 {
namespace {

constexpr std::uint32_t header_magic = 0x43504a55u; /* 'UJPC' */
constexpr std::uint32_t record_magic = 0x54534a50u; /* 'PJST' */
constexpr std::uint32_t format_version = 1;
constexpr std::size_t header_bytes = 4096;
constexpr std::uint32_t flag_has_page_hash = 1u;
constexpr std::uint32_t flag_has_mtime = 2u;
constexpr std::uint32_t flag_has_size = 4u;
constexpr std::uint32_t flag_has_uuid = 8u;

[[nodiscard]] std::uint64_t wyhash64(std::uint64_t value) noexcept
{
	value += 0x9e3779b97f4a7c15ULL;
	value = (value ^ (value >> 30)) * 0xbf58476d1ce4e5b9ULL;
	value = (value ^ (value >> 27)) * 0x94d049bb133111ebULL;
	return value ^ (value >> 31);
}

[[nodiscard]] std::uint32_t
crc32_of(std::span<const std::byte> bytes) noexcept
{
	std::uint32_t crc = 0xffffffffu;
	for (const auto byte : bytes) {
		crc ^= static_cast<std::uint8_t>(byte);
		for (int bit = 0; bit < 8; ++bit) {
			const auto bit0 = crc & 1u;
			crc >>= 1;
			if (bit0)
				crc ^= 0xedb88320u;
		}
	}
	return ~crc;
}

} // namespace

std::array<std::uint8_t, 16>
persistent_content_hash(std::span<const std::byte> bytes) noexcept
{
	std::uint64_t lo = 0x243f6a8885a308d3ULL;
	std::uint64_t hi = 0x13198a2e03707344ULL;
	const auto *data = reinterpret_cast<const std::uint8_t *>(bytes.data());
	std::size_t remaining = bytes.size();
	std::size_t offset = 0;
	while (remaining >= 8) {
		std::uint64_t word = 0;
		std::memcpy(&word, data + offset, 8);
		lo = wyhash64(lo ^ word);
		hi = wyhash64(hi ^ wyhash64(word + remaining));
		offset += 8;
		remaining -= 8;
	}
	std::uint64_t tail = static_cast<std::uint64_t>(remaining);
	if (remaining != 0)
		std::memcpy(&tail, data + offset, remaining);
	lo = wyhash64(lo ^ tail ^ (bytes.size() * 0x9e3779b97f4a7c15ULL));
	hi = wyhash64(hi ^ lo);
	std::array<std::uint8_t, 16> out{};
	std::memcpy(out.data(), &lo, 8);
	std::memcpy(out.data() + 8, &hi, 8);
	return out;
}

namespace {

[[nodiscard]] std::array<std::uint8_t, 16> hash_profile(
	const SharedTranslationCache::CodegenProfile &profile) noexcept
{
	std::vector<std::byte> packed;
	packed.reserve(32 + (uml::platform::arm_feature_count + 7) / 8);
	packed.push_back(static_cast<std::byte>(profile.translation_mode));
	const auto &cap = profile.capabilities;
	std::uint8_t bits = 0;
	std::size_t filled = 0;
	for (std::size_t index = 0; index < uml::platform::arm_feature_count;
	     ++index) {
		if (cap.supported.test(index))
			bits |= static_cast<std::uint8_t>(1u << filled);
		++filled;
		if (filled == 8) {
			packed.push_back(static_cast<std::byte>(bits));
			bits = 0;
			filled = 0;
		}
	}
	if (filled != 0)
		packed.push_back(static_cast<std::byte>(bits));
	const auto push_bool = [&](bool value) {
		packed.push_back(static_cast<std::byte>(value ? 1 : 0));
	};
	push_bool(cap.floating_point);
	push_bool(cap.advanced_simd);
	push_bool(cap.fp16);
	push_bool(cap.cssc);
	push_bool(cap.aes);
	push_bool(cap.pmull);
	push_bool(cap.sha1);
	push_bool(cap.sha2);
	push_bool(cap.crc32);
	push_bool(cap.sha3);
	push_bool(cap.sha512);
	push_bool(cap.jscvt_subnormal_flags_correct);
	push_bool(cap.sme_hardware);
	packed.push_back(static_cast<std::byte>(cap.sme_svl_bytes & 0xff));
	packed.push_back(static_cast<std::byte>((cap.sme_svl_bytes >> 8) & 0xff));
	return persistent_content_hash(packed);
}

struct FileHeader final {
	std::uint32_t magic{header_magic};
	std::uint32_t version{format_version};
	std::uint64_t page_size{::uml::cpu::arm64::page_size};
	std::uint64_t source_mtime{};
	std::uint64_t source_size{};
	std::array<std::uint8_t, 16> source_uuid{};
	std::uint32_t flags{};
	std::uint32_t reserved{};
	std::uint64_t entry_count{};
	std::uint64_t data_end{header_bytes};
	std::uint32_t crc{};
};

struct RelocDisk final {
	std::uint32_t word{};
	std::uint32_t kind{};
	std::uint64_t key{};
};

struct RecordPrefix final {
	std::uint32_t magic{record_magic};
	std::uint32_t size{};
	std::uint32_t crc{};
	std::uint32_t flags{};
	std::array<std::uint8_t, 16> page_hash{};
	std::array<std::uint8_t, 16> profile_hash{};
	std::uint32_t page_offset{};
	std::uint8_t isa{};
	std::uint8_t bools{};
	std::uint16_t reserved{};
	std::uint64_t recorded_pc{};
	std::uint32_t guest_word_count{};
	std::uint32_t guest_instructions{};
	std::uint32_t host_word_count{};
	std::uint32_t reloc_count{};
	std::uint32_t hot_words{};
	std::uint32_t internal_entry_word{};
	std::uint64_t memory_write_mask{};
	std::uint64_t direct_memory_write_mask{};
};

struct IndexKey final {
	std::array<std::uint8_t, 16> page_hash{};
	std::array<std::uint8_t, 16> profile_hash{};
	std::uint32_t page_offset{};

	[[nodiscard]] bool operator==(const IndexKey &) const noexcept = default;
};

struct IndexKeyHash final {
	[[nodiscard]] std::size_t operator()(const IndexKey &key) const noexcept
	{
		std::uint64_t lo = 0;
		std::uint64_t mid = 0;
		std::memcpy(&lo, key.page_hash.data(), 8);
		std::memcpy(&mid, key.profile_hash.data(), 8);
		return static_cast<std::size_t>(wyhash64(
			lo ^ mid ^ (static_cast<std::uint64_t>(key.page_offset) << 1)));
	}
};

struct IndexEntry final {
	std::uint64_t offset{};
	std::uint32_t size{};
};

[[nodiscard]] bool read_exactly(int fd, void *buffer, std::size_t bytes,
	off_t offset) noexcept
{
	auto *cursor = static_cast<std::byte *>(buffer);
	std::size_t left = bytes;
	while (left != 0) {
		const auto got = ::pread(fd, cursor, left, offset);
		if (got == 0)
			return false;
		if (got < 0) {
			if (errno == EINTR)
				continue;
			return false;
		}
		cursor += static_cast<std::size_t>(got);
		offset += got;
		left -= static_cast<std::size_t>(got);
	}
	return true;
}

[[nodiscard]] bool write_exactly(int fd, const void *buffer, std::size_t bytes,
	off_t offset) noexcept
{
	auto *cursor = static_cast<const std::byte *>(buffer);
	std::size_t left = bytes;
	while (left != 0) {
		const auto put = ::pwrite(fd, cursor, left, offset);
		if (put < 0) {
			if (errno == EINTR)
				continue;
			return false;
		}
		cursor += static_cast<std::size_t>(put);
		offset += put;
		left -= static_cast<std::size_t>(put);
	}
	return true;
}

[[nodiscard]] std::uint32_t header_crc(const FileHeader &header) noexcept
{
	FileHeader copy = header;
	copy.crc = 0;
	return crc32_of({reinterpret_cast<const std::byte *>(&copy), sizeof(copy)});
}

[[nodiscard]] FileHeader make_header(const PersistentIdentity &source)
{
	FileHeader header{};
	header.source_mtime = source.source_mtime;
	header.source_size = source.source_size;
	header.source_uuid = source.source_uuid;
	if (source.has_mtime)
		header.flags |= flag_has_mtime;
	if (source.has_size)
		header.flags |= flag_has_size;
	if (source.has_uuid)
		header.flags |= flag_has_uuid;
	header.crc = header_crc(header);
	return header;
}

[[nodiscard]] bool header_valid(const FileHeader &header) noexcept
{
	return header.magic == header_magic && header.version == format_version &&
	       header.page_size == ::uml::cpu::arm64::page_size &&
	       header.data_end >= header_bytes && header.crc == header_crc(header);
}

[[nodiscard]] bool header_matches_source(const FileHeader &header,
	const PersistentIdentity &source) noexcept
{
	if (!header_valid(header))
		return false;
	if (source.has_uuid && (header.flags & flag_has_uuid) != 0 &&
	    source.source_uuid != header.source_uuid)
		return false;
	if (source.has_size && (header.flags & flag_has_size) != 0 &&
	    source.source_size != header.source_size)
		return false;
	if (source.has_mtime && (header.flags & flag_has_mtime) != 0 &&
	    source.source_mtime != header.source_mtime)
		return false;
	return true;
}

void retire_path(const std::filesystem::path &path)
{
	if (!std::filesystem::exists(path))
		return;
	auto bak = path;
	bak += ".stale";
	std::error_code ec;
	std::filesystem::rename(path, bak, ec);
	if (ec)
		std::filesystem::remove(path, ec);
}

[[nodiscard]] std::optional<std::array<std::uint8_t, 16>>
read_ext4_uuid(const std::filesystem::path &path) noexcept
{
	const auto fd = ::open(path.c_str(), O_RDONLY);
	if (fd < 0)
		return std::nullopt;
	std::array<std::byte, 1024> super{};
	const auto ok = read_exactly(fd, super.data(), super.size(), 1024);
	::close(fd);
	if (!ok)
		return std::nullopt;
	std::uint16_t magic = 0;
	std::memcpy(&magic, super.data() + 0x38, 2);
	if (magic != 0xef53)
		return std::nullopt;
	std::array<std::uint8_t, 16> uuid{};
	std::memcpy(uuid.data(), super.data() + 0x68, 16);
	return uuid;
}

[[nodiscard]] std::size_t guest_identity_elements_of(
	const SharedTranslation &translation) noexcept
{
	const auto bytes = translation.guest_word_count *
			   aarch32::isa_unit_bytes(
				   static_cast<aarch32::GuestIsa>(translation.isa));
	return (bytes + sizeof(std::uint32_t) - 1U) / sizeof(std::uint32_t);
}

} // namespace

PersistentIdentity
fingerprint_persistent_source(const std::filesystem::path &path)
{
	PersistentIdentity identity{};
	struct stat status {};
	if (::stat(path.c_str(), &status) != 0)
		return identity;
	identity.source_mtime = static_cast<std::uint64_t>(status.st_mtime);
	identity.source_size = static_cast<std::uint64_t>(status.st_size);
	identity.has_mtime = true;
	identity.has_size = true;
	if (auto uuid = read_ext4_uuid(path)) {
		identity.source_uuid = *uuid;
		identity.has_uuid = true;
	}
	return identity;
}

struct PersistentTranslationStore::Impl final {
	std::filesystem::path directory;
	std::filesystem::path data_path;
	std::filesystem::path index_path;
	PersistentIdentity source{};
	FileHeader header{};
	int data_fd{-1};
	std::unordered_map<IndexKey, IndexEntry, IndexKeyHash> index;
	mutable std::mutex mutex;
	std::atomic<std::uint64_t> hits{};
	std::atomic<std::uint64_t> stores{};
	std::atomic<std::uint64_t> rejected{};
	std::uint64_t unsynced{};

	~Impl()
	{
		if (data_fd >= 0) {
			::close(data_fd);
			data_fd = -1;
		}
	}

	[[nodiscard]] bool write_header() const
	{
		FileHeader out = header;
		out.crc = 0;
		out.crc = header_crc(out);
		std::array<std::byte, header_bytes> block{};
		std::memcpy(block.data(), &out, sizeof(out));
		return write_exactly(data_fd, block.data(), block.size(), 0);
	}

	void install_index(const IndexKey &key, std::uint64_t offset,
		std::uint32_t size)
	{
		index[key] = IndexEntry{offset, size};
	}

	void scan_data()
	{
		index.clear();
		std::uint64_t cursor = header_bytes;
		std::uint64_t entries = 0;
		const auto end = header.data_end;
		while (cursor + sizeof(RecordPrefix) <= end) {
			RecordPrefix prefix{};
			if (!read_exactly(data_fd, &prefix, sizeof(prefix),
				    static_cast<off_t>(cursor)))
				break;
			if (prefix.magic != record_magic || prefix.size < sizeof(prefix) ||
			    cursor + prefix.size > end)
				break;
			std::vector<std::byte> record(prefix.size);
			if (!read_exactly(data_fd, record.data(), record.size(),
				    static_cast<off_t>(cursor)))
				break;
			RecordPrefix check{};
			std::memcpy(&check, record.data(), sizeof(check));
			const auto stored_crc = check.crc;
			check.crc = 0;
			std::memcpy(record.data(), &check, sizeof(check));
			if (crc32_of(record) != stored_crc) {
				++rejected;
				break;
			}
			if ((check.flags & flag_has_page_hash) == 0) {
				cursor += prefix.size;
				continue;
			}
			install_index(IndexKey{check.page_hash, check.profile_hash,
					      check.page_offset},
				cursor, prefix.size);
			++entries;
			cursor += prefix.size;
		}
		header.entry_count = entries;
		header.data_end = cursor;
	}

	void write_index_file()
	{
		const auto tmp = index_path.string() + ".tmp";
		const auto fd = ::open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
		if (fd < 0)
			return;
		const auto count = static_cast<std::uint64_t>(index.size());
		const auto data_end = header.data_end;
		bool ok = write_exactly(fd, &count, sizeof(count), 0) &&
			  write_exactly(fd, &data_end, sizeof(data_end), 8);
		off_t offset = 16;
		for (const auto &[key, entry] : index) {
			if (!ok)
				break;
			ok = write_exactly(fd, &key, sizeof(key), offset) &&
			     write_exactly(fd, &entry, sizeof(entry),
				     offset + static_cast<off_t>(sizeof(key)));
			offset += static_cast<off_t>(sizeof(key) + sizeof(entry));
		}
		if (ok)
			::fsync(fd);
		::close(fd);
		if (ok) {
			std::error_code ec;
			std::filesystem::rename(tmp, index_path, ec);
		} else {
			::unlink(tmp.c_str());
		}
	}

	[[nodiscard]] bool load_index_file()
	{
		const auto fd = ::open(index_path.c_str(), O_RDONLY);
		if (fd < 0)
			return false;
		std::uint64_t count = 0;
		std::uint64_t data_end = 0;
		bool ok = read_exactly(fd, &count, sizeof(count), 0) &&
			  read_exactly(fd, &data_end, sizeof(data_end), 8);
		if (!ok || data_end != header.data_end) {
			::close(fd);
			return false;
		}
		index.clear();
		index.reserve(static_cast<std::size_t>(count));
		off_t offset = 16;
		for (std::uint64_t i = 0; i < count; ++i) {
			IndexKey key{};
			IndexEntry entry{};
			if (!read_exactly(fd, &key, sizeof(key), offset) ||
			    !read_exactly(fd, &entry, sizeof(entry),
				    offset + static_cast<off_t>(sizeof(key)))) {
				::close(fd);
				index.clear();
				return false;
			}
			index.emplace(key, entry);
			offset += static_cast<off_t>(sizeof(key) + sizeof(entry));
		}
		::close(fd);
		header.entry_count = count;
		return true;
	}
};

PersistentTranslationStore::~PersistentTranslationStore()
{
	flush();
}

std::shared_ptr<PersistentTranslationStore> PersistentTranslationStore::open(
	const std::filesystem::path &directory, PersistentIdentity source)
{
	std::error_code ec;
	std::filesystem::create_directories(directory, ec);
	auto store = std::shared_ptr<PersistentTranslationStore>(
		new PersistentTranslationStore());
	store->impl_ = std::make_unique<Impl>();
	auto &impl = *store->impl_;
	impl.directory = directory;
	impl.data_path = directory / "data.jtc";
	impl.index_path = directory / "index.jtc";
	impl.source = source;

	auto header = FileHeader{};
	const auto existing = ::open(impl.data_path.c_str(), O_RDWR);
	bool reuse = false;
	if (existing >= 0) {
		std::array<std::byte, header_bytes> block{};
		if (read_exactly(existing, block.data(), block.size(), 0)) {
			std::memcpy(&header, block.data(), sizeof(header));
			if (header_matches_source(header, source))
				reuse = true;
		}
		if (!reuse) {
			::close(existing);
			retire_path(impl.data_path);
			retire_path(impl.index_path);
		} else {
			impl.data_fd = existing;
			impl.header = header;
		}
	}
	if (!reuse) {
		impl.data_fd =
			::open(impl.data_path.c_str(), O_RDWR | O_CREAT | O_TRUNC, 0644);
		if (impl.data_fd < 0)
			return {};
		impl.header = make_header(source);
		if (!impl.write_header())
			return {};
	}
	if (reuse && !impl.load_index_file())
		impl.scan_data();
	return store;
}

void PersistentTranslationStore::remember(
	const SharedTranslationCache::CodegenProfile &profile,
	const SharedTranslation &translation, const PersistentIdentity &identity)
{
	if (!impl_ || impl_->data_fd < 0 || !identity.has_page_hash)
		return;
	if (translation.guest_words == nullptr || translation.words.empty() ||
	    translation.guest_word_count == 0)
		return;
	const auto guest_elements = guest_identity_elements_of(translation);
	const auto profile_hash = hash_profile(profile);
	const IndexKey key{identity.page_hash, profile_hash,
		static_cast<std::uint32_t>(
			translation.recorded_pc & (page_size - 1U))};

	std::vector<RelocDisk> relocs(translation.relocations.size());
	std::vector<std::uint32_t> host(translation.words.begin(),
		translation.words.end());
	for (std::size_t i = 0; i < translation.relocations.size(); ++i) {
		relocs[i].word = static_cast<std::uint32_t>(translation.relocations[i].word);
		relocs[i].kind = static_cast<std::uint32_t>(translation.relocations[i].kind);
		relocs[i].key = translation.relocations[i].key;
		if (relocs[i].word + 1U >= host.size())
			return;
		host[relocs[i].word] = 0;
		host[relocs[i].word + 1U] = 0;
	}
	/* A leftover host pointer (for example a publisher link record)
	 * would jump into the previous process after reload. Refuse it. */
	for (std::size_t i = 0; i + 1U < host.size(); i += 2) {
		const auto value = static_cast<std::uint64_t>(host[i]) |
				   (static_cast<std::uint64_t>(host[i + 1U]) << 32);
		if (value >= 0x100000000ull && value < 0x200000000ull)
			return;
	}
	const auto payload = sizeof(RecordPrefix) +
			     guest_elements * sizeof(std::uint32_t) +
			     translation.words.size() * sizeof(std::uint32_t) +
			     relocs.size() * sizeof(RelocDisk);
	std::vector<std::byte> record(payload);
	RecordPrefix prefix{};
	prefix.magic = record_magic;
	prefix.size = static_cast<std::uint32_t>(payload);
	prefix.flags = flag_has_page_hash;
	prefix.page_hash = identity.page_hash;
	prefix.profile_hash = profile_hash;
	prefix.page_offset = key.page_offset;
	prefix.isa = translation.isa;
	prefix.bools = static_cast<std::uint8_t>(
		(translation.accesses_fp_state ? 1u : 0u) |
		(translation.link_target_safe ? 2u : 0u) |
		(translation.native_fp ? 4u : 0u) |
		(translation.guest_illegal ? 8u : 0u));
	prefix.recorded_pc = translation.recorded_pc;
	prefix.guest_word_count = static_cast<std::uint32_t>(translation.guest_word_count);
	prefix.guest_instructions =
		static_cast<std::uint32_t>(translation.guest_instructions);
	prefix.host_word_count = static_cast<std::uint32_t>(translation.words.size());
	prefix.reloc_count = static_cast<std::uint32_t>(relocs.size());
	prefix.hot_words = static_cast<std::uint32_t>(translation.hot_words);
	prefix.internal_entry_word =
		static_cast<std::uint32_t>(translation.internal_entry_word);
	prefix.memory_write_mask = translation.memory_write_mask;
	prefix.direct_memory_write_mask = translation.direct_memory_write_mask;

	auto *cursor = record.data();
	std::memcpy(cursor, &prefix, sizeof(prefix));
	cursor += sizeof(prefix);
	std::memcpy(cursor, translation.guest_words.get(),
		guest_elements * sizeof(std::uint32_t));
	cursor += guest_elements * sizeof(std::uint32_t);
	std::memcpy(cursor, host.data(),
		host.size() * sizeof(std::uint32_t));
	cursor += host.size() * sizeof(std::uint32_t);
	if (!relocs.empty())
		std::memcpy(cursor, relocs.data(), relocs.size() * sizeof(RelocDisk));

	prefix.crc = 0;
	std::memcpy(record.data(), &prefix, sizeof(prefix));
	prefix.crc = crc32_of(record);
	std::memcpy(record.data(), &prefix, sizeof(prefix));

	std::lock_guard lock{impl_->mutex};
	if (impl_->index.contains(key))
		return;
	const auto offset = impl_->header.data_end;
	if (!write_exactly(impl_->data_fd, record.data(), record.size(),
		    static_cast<off_t>(offset))) {
		++impl_->rejected;
		return;
	}
	impl_->header.data_end = offset + record.size();
	++impl_->header.entry_count;
	impl_->install_index(key, offset, prefix.size);
	++impl_->stores;
	++impl_->unsynced;
	if (impl_->unsynced >= 4096) {
		(void)impl_->write_header();
		::fsync(impl_->data_fd);
		impl_->write_index_file();
		impl_->unsynced = 0;
	}
}

std::shared_ptr<SharedTranslation> PersistentTranslationStore::lookup(
	const SharedTranslationCache::CodegenProfile &profile,
	std::uint64_t guest_pc, std::span<const std::uint32_t> guest_words,
	const PersistentIdentity &identity) const
{
	if (!impl_ || impl_->data_fd < 0 || !identity.has_page_hash)
		return nullptr;
	const IndexKey key{identity.page_hash, hash_profile(profile),
		static_cast<std::uint32_t>(guest_pc & (page_size - 1U))};
	IndexEntry entry{};
	{
		std::lock_guard lock{impl_->mutex};
		const auto found = impl_->index.find(key);
		if (found == impl_->index.end())
			return nullptr;
		entry = found->second;
	}
	std::vector<std::byte> record(entry.size);
	if (!read_exactly(impl_->data_fd, record.data(), record.size(),
		    static_cast<off_t>(entry.offset))) {
		++impl_->rejected;
		return nullptr;
	}
	if (record.size() < sizeof(RecordPrefix)) {
		++impl_->rejected;
		return nullptr;
	}
	RecordPrefix prefix{};
	std::memcpy(&prefix, record.data(), sizeof(prefix));
	const auto stored_crc = prefix.crc;
	prefix.crc = 0;
	std::memcpy(record.data(), &prefix, sizeof(prefix));
	if (prefix.magic != record_magic || stored_crc != crc32_of(record)) {
		++impl_->rejected;
		return nullptr;
	}
	const auto guest_elements =
		(prefix.guest_word_count * aarch32::isa_unit_bytes(
			 static_cast<aarch32::GuestIsa>(prefix.isa)) +
			sizeof(std::uint32_t) - 1U) /
		sizeof(std::uint32_t);
	const auto expected = sizeof(RecordPrefix) +
			      guest_elements * sizeof(std::uint32_t) +
			      static_cast<std::size_t>(prefix.host_word_count) *
				      sizeof(std::uint32_t) +
			      static_cast<std::size_t>(prefix.reloc_count) *
				      sizeof(RelocDisk);
	if (expected != record.size() || guest_elements == 0 ||
	    guest_elements > guest_words.size()) {
		++impl_->rejected;
		return nullptr;
	}
	const auto *guest = reinterpret_cast<const std::uint32_t *>(
		record.data() + sizeof(RecordPrefix));
	const auto identity_bytes =
		prefix.guest_word_count *
		aarch32::isa_unit_bytes(static_cast<aarch32::GuestIsa>(prefix.isa));
	if (std::memcmp(guest, guest_words.data(), identity_bytes) != 0) {
		++impl_->rejected;
		return nullptr;
	}
	const auto *host = guest + guest_elements;
	const auto *relocs = reinterpret_cast<const RelocDisk *>(
		reinterpret_cast<const std::byte *>(host) +
		static_cast<std::size_t>(prefix.host_word_count) * sizeof(std::uint32_t));
	std::vector<JitRelocation> relocations(prefix.reloc_count);
	for (std::uint32_t i = 0; i < prefix.reloc_count; ++i) {
		relocations[i].word = relocs[i].word;
		relocations[i].key = relocs[i].key;
		relocations[i].kind = static_cast<JitRelocationKind>(relocs[i].kind);
	}
	for (std::uint32_t i = 0; i < prefix.reloc_count; ++i) {
		if (relocs[i].word + 1U >= prefix.host_word_count) {
			++impl_->rejected;
			return nullptr;
		}
	}
	for (std::uint32_t i = 0; i + 1U < prefix.host_word_count; i += 2) {
		const auto value = static_cast<std::uint64_t>(host[i]) |
				   (static_cast<std::uint64_t>(host[i + 1U]) << 32);
		bool reloc_cell = false;
		for (std::uint32_t r = 0; r < prefix.reloc_count; ++r)
			if (relocs[r].word == i)
				reloc_cell = true;
		if (reloc_cell)
			continue;
		if (value >= 0x100000000ull && value < 0x200000000ull) {
			++impl_->rejected;
			return nullptr;
		}
	}
	auto translation = make_packed_shared_translation(
		{host, prefix.host_word_count}, relocations, {guest, guest_elements});
	translation->isa = prefix.isa;
	translation->guest_word_count = prefix.guest_word_count;
	translation->guest_instructions = prefix.guest_instructions;
	translation->hot_words = prefix.hot_words;
	translation->internal_entry_word = prefix.internal_entry_word;
	translation->memory_write_mask = prefix.memory_write_mask;
	translation->direct_memory_write_mask = prefix.direct_memory_write_mask;
	translation->accesses_fp_state = (prefix.bools & 1u) != 0;
	translation->link_target_safe = (prefix.bools & 2u) != 0;
	translation->native_fp = (prefix.bools & 4u) != 0;
	translation->guest_illegal = (prefix.bools & 8u) != 0;
	translation->recorded_pc = prefix.recorded_pc;
	translation->code_page_identity = 0;
	translation->code_page_version = 0;
	++impl_->hits;
	return translation;
}

void PersistentTranslationStore::flush()
{
	if (!impl_ || impl_->data_fd < 0)
		return;
	std::lock_guard lock{impl_->mutex};
	(void)impl_->write_header();
	::fsync(impl_->data_fd);
	impl_->write_index_file();
	impl_->unsynced = 0;
}

PersistentTranslationStatistics
PersistentTranslationStore::statistics() const noexcept
{
	PersistentTranslationStatistics stats{};
	if (!impl_)
		return stats;
	std::lock_guard lock{impl_->mutex};
	stats.hits = impl_->hits;
	stats.stores = impl_->stores;
	stats.rejected = impl_->rejected;
	stats.entries = impl_->header.entry_count;
	stats.data_bytes = impl_->header.data_end;
	return stats;
}

std::shared_ptr<PersistentTranslationStore>
open_persistent_translation_store_from_environment()
{
	const char *directory = std::getenv("KERNARIUM_JIT_PERSISTENT_CACHE");
	if (directory == nullptr || directory[0] == '\0')
		directory = std::getenv("UML_JIT_PERSISTENT_CACHE");
	if (directory == nullptr || directory[0] == '\0')
		return {};
	PersistentIdentity source{};
	const char *origin = std::getenv("KERNARIUM_JIT_PERSISTENT_CACHE_SOURCE");
	if (origin == nullptr || origin[0] == '\0')
		origin = std::getenv("UML_JIT_PERSISTENT_CACHE_SOURCE");
	if (origin != nullptr && origin[0] != '\0')
		source = fingerprint_persistent_source(origin);
	return PersistentTranslationStore::open(directory, source);
}


namespace {
thread_local PersistentIdentity thread_identity{};
thread_local bool thread_identity_bound{};
} // namespace

ThreadPersistentIdentityScope::ThreadPersistentIdentityScope(
	PersistentIdentity identity) noexcept
{
	thread_identity = identity;
	thread_identity_bound = identity.has_page_hash;
}

ThreadPersistentIdentityScope::~ThreadPersistentIdentityScope()
{
	thread_identity = {};
	thread_identity_bound = false;
}

const PersistentIdentity *thread_persistent_identity() noexcept
{
	return thread_identity_bound ? &thread_identity : nullptr;
}

} // namespace uml::cpu::arm64
