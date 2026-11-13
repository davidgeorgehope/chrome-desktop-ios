// SPDX-License-Identifier: GPL-2.0-or-later
#include "cpu/arm64/jit/jit_persistent_translations.hpp"
#include "cpu/arm64/jit/jit_shared_translations.hpp"
#include "cpu/arm64/aarch32/guest_key.hpp"
#include "require.hpp"

#include <array>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <filesystem>
#include <span>
#include <string>
#include <unistd.h>
#include <vector>

namespace {

namespace arm64 = uml::cpu::arm64;
using uml::testing::require;

[[nodiscard]] std::filesystem::path make_temp_dir()
{
	auto path = std::filesystem::temp_directory_path() /
		    ("uml-persist-" + std::to_string(::getpid()) + "-" +
			    std::to_string(reinterpret_cast<std::uintptr_t>(&path)));
	std::filesystem::remove_all(path);
	std::filesystem::create_directories(path);
	return path;
}

[[nodiscard]] std::shared_ptr<arm64::SharedTranslation>
make_block(std::span<const std::uint32_t> guest, std::uint64_t recorded_pc,
	std::uint32_t host_mark)
{
	std::array<std::uint32_t, 4> host{host_mark, host_mark + 1, 0, 0};
	auto translation = arm64::make_packed_shared_translation(host, {}, guest);
	translation->isa = 0; /* A64 */
	translation->guest_word_count = guest.size();
	translation->guest_instructions = guest.size();
	translation->hot_words = 2;
	translation->internal_entry_word = 1;
	translation->recorded_pc = recorded_pc;
	return translation;
}

void store_round_trip_and_content_mismatch_falls_back()
{
	const auto dir = make_temp_dir();
	const arm64::SharedTranslationCache::CodegenProfile profile{};
	const std::array guest{0xd503201fU};
	const std::uint64_t pc = 0x1000;
	std::array<std::byte, 16> page{};
	std::memcpy(page.data(), guest.data(), sizeof(guest[0]));
	arm64::PersistentIdentity identity{};
	identity.page_hash = arm64::persistent_content_hash(page);
	identity.has_page_hash = true;

	{
		auto store = arm64::PersistentTranslationStore::open(dir, {});
		require(store != nullptr);
		auto translation = make_block(guest, pc, 0x11);
		store->remember(profile, *translation, identity);
		store->flush();
		require(store->statistics().stores == 1);
		require(store->statistics().entries == 1);
	}

	{
		auto store = arm64::PersistentTranslationStore::open(dir, {});
		require(store != nullptr);
		require(store->statistics().entries == 1);
		const auto loaded = store->lookup(profile, pc, guest, identity);
		require(loaded != nullptr);
		require(loaded->recorded_pc == pc);
		require(loaded->words.size() >= 2);
		require(loaded->words[0] == 0x11);
		require(store->statistics().hits == 1);
	}

	{
		auto store = arm64::PersistentTranslationStore::open(dir, {});
		std::array<std::uint32_t, 1> other{0xd4200000U};
		/* Same page hash would be a lie; a changed page hashes differently. */
		std::array<std::byte, 16> other_page{};
		std::memcpy(other_page.data(), other.data(), sizeof(other[0]));
		arm64::PersistentIdentity other_id{};
		other_id.page_hash = arm64::persistent_content_hash(other_page);
		other_id.has_page_hash = true;
		require(store->lookup(profile, pc, other, other_id) == nullptr);
		/* Same key, different guest bytes: content check rejects. */
		require(store->lookup(profile, pc, other, identity) == nullptr);
		require(store->statistics().rejected >= 1);
	}

	std::filesystem::remove_all(dir);
}

void source_fingerprint_mismatch_starts_empty()
{
	const auto dir = make_temp_dir();
	const auto src = dir / "rootfs.ext4";
	/* Minimal fake ext4 superblock so size/mtime are recorded. */
	std::vector<std::byte> image(2048);
	std::uint16_t magic = 0xef53;
	std::memcpy(image.data() + 1024 + 0x38, &magic, 2);
	std::array<std::uint8_t, 16> uuid{
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
	std::memcpy(image.data() + 1024 + 0x68, uuid.data(), 16);
	{
		auto *fp = std::fopen(src.c_str(), "wb");
		require(fp != nullptr);
		require(std::fwrite(image.data(), 1, image.size(), fp) == image.size());
		std::fclose(fp);
	}
	const auto first = arm64::fingerprint_persistent_source(src);
	require(first.has_size);
	require(first.has_mtime);
	require(first.has_uuid);
	require(first.source_uuid == uuid);

	const arm64::SharedTranslationCache::CodegenProfile profile{};
	const std::array guest{0xd503201fU};
	std::array<std::byte, 16> page{};
	std::memcpy(page.data(), guest.data(), sizeof(guest[0]));
	arm64::PersistentIdentity identity{};
	identity.page_hash = arm64::persistent_content_hash(page);
	identity.has_page_hash = true;
	{
		auto store = arm64::PersistentTranslationStore::open(dir, first);
		auto translation = make_block(guest, 0x1000, 0x22);
		store->remember(profile, *translation, identity);
		store->flush();
		require(store->statistics().entries == 1);
	}

	/* Change UUID as if a different image landed at the same path. */
	uuid[0] = 0x99;
	std::memcpy(image.data() + 1024 + 0x68, uuid.data(), 16);
	{
		auto *fp = std::fopen(src.c_str(), "wb");
		require(fp != nullptr);
		require(std::fwrite(image.data(), 1, image.size(), fp) == image.size());
		std::fclose(fp);
	}
	const auto second = arm64::fingerprint_persistent_source(src);
	auto store = arm64::PersistentTranslationStore::open(dir, second);
	require(store->statistics().entries == 0);
	require(store->lookup(profile, 0x1000, guest, identity) == nullptr);
	std::filesystem::remove_all(dir);
}

void ram_cache_reuses_store_across_instances()
{
	const auto dir = make_temp_dir();
	const arm64::SharedTranslationCache::CodegenProfile profile{};
	const std::array guest{0xd503201fU};
	const std::uint64_t pc = 0x2000;
	std::array<std::byte, 16> page{};
	std::memcpy(page.data(), guest.data(), sizeof(guest[0]));
	arm64::PersistentIdentity identity{};
	identity.page_hash = arm64::persistent_content_hash(page);
	identity.has_page_hash = true;

	{
		arm64::SharedTranslationCache cache;
		cache.attach_persistent_store(
			arm64::PersistentTranslationStore::open(dir, {}));
		cache.add_executor();
		arm64::ThreadPersistentIdentityScope bound{identity};
		const auto inserted = cache.insert(profile, pc, guest, make_block(guest, pc, 0x33));
		require(inserted != nullptr);
		cache.remove_executor();
	}

	arm64::SharedTranslationCache warm;
	warm.attach_persistent_store(
		arm64::PersistentTranslationStore::open(dir, {}));
	warm.add_executor();
	arm64::ThreadPersistentIdentityScope bound{identity};
	const auto found = warm.find(profile, pc + 0x10000, guest, 7, 1);
	require(found != nullptr);
	require(found->recorded_pc == pc);
	require(found->words[0] == 0x33);
	require(found->code_page_identity == 7);
	require(found->code_page_version == 1);
	require(warm.statistics().matches >= 1);
	warm.remove_executor();
	std::filesystem::remove_all(dir);
}

} // namespace

int main()
{
	store_round_trip_and_content_mismatch_falls_back();
	source_fingerprint_mismatch_starts_empty();
	ram_cache_reuses_store_across_instances();
	return 0;
}
