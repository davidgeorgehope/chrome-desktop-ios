// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "jit_shared_translations.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <span>
#include <string>

namespace uml::cpu::arm64 {

/* Durable identity for a shared translation that must survive process
 * exit and reboot. The in-memory location key uses a process-lifetime
 * code-page stamp, which is not stable. This identity is the content
 * hash of the guest code page plus the offset of the block in that page,
 * plus an optional fingerprint of the source image (size, mtime, and
 * ext4 UUID when the path is an ext4 rootfs).
 */
struct PersistentIdentity final {
  std::array<std::uint8_t, 16> page_hash{};
  bool has_page_hash{};
  std::uint64_t source_mtime{};
  std::uint64_t source_size{};
  std::array<std::uint8_t, 16> source_uuid{};
  bool has_mtime{};
  bool has_size{};
  bool has_uuid{};
};

struct PersistentTranslationStatistics final {
  std::uint64_t hits{};
  std::uint64_t stores{};
  std::uint64_t rejected{};
  std::uint64_t entries{};
  std::uint64_t data_bytes{};
};

/* Content hash used as the durable page identity. */
[[nodiscard]] std::array<std::uint8_t, 16>
persistent_content_hash(std::span<const std::byte> bytes) noexcept;

[[nodiscard]] PersistentIdentity
fingerprint_persistent_source(const std::filesystem::path &path);

class PersistentTranslationStore final {
public:
  ~PersistentTranslationStore();

  PersistentTranslationStore(const PersistentTranslationStore &) = delete;
  PersistentTranslationStore &operator=(
      const PersistentTranslationStore &) = delete;

  /* Opens (or creates) directory/data.jtc and directory/index.jtc.
   * If source fingerprint disagrees with the file header, the existing
   * files are retired (renamed aside) and a new cache is started.
   * A corrupt record is skipped; a corrupt header falls back to empty.
   */
  [[nodiscard]] static std::shared_ptr<PersistentTranslationStore>
  open(const std::filesystem::path &directory, PersistentIdentity source);

  void remember(const SharedTranslationCache::CodegenProfile &profile,
                const SharedTranslation &translation,
                const PersistentIdentity &identity);
  /* Returns a packed translation whose recorded_pc is the original
   * compile PC (so materialization can slide) and whose process-local
   * stamp fields are left zero. The caller writes the current stamp
   * before admitting the entry to the RAM cache.
   */
  [[nodiscard]] std::shared_ptr<SharedTranslation>
  lookup(const SharedTranslationCache::CodegenProfile &profile,
         std::uint64_t guest_pc, std::span<const std::uint32_t> guest_words,
         const PersistentIdentity &identity) const;

  void flush();

  [[nodiscard]] PersistentTranslationStatistics statistics() const noexcept;

private:
  PersistentTranslationStore() = default;
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

/* Env: UML_JIT_PERSISTENT_CACHE or KERNARIUM_JIT_PERSISTENT_CACHE is the
 * directory. UML_JIT_PERSISTENT_CACHE_SOURCE / KERNARIUM_JIT_PERSISTENT_CACHE_SOURCE
 * is an optional rootfs path used as the source fingerprint.
 */
[[nodiscard]] std::shared_ptr<PersistentTranslationStore>
open_persistent_translation_store_from_environment();

/* Set for the duration of one find/publish on this thread so the RAM cache
 * can consult and update the store without adding arguments to every
 * call site.
 */
class ThreadPersistentIdentityScope final {
public:
  explicit ThreadPersistentIdentityScope(PersistentIdentity identity) noexcept;
  ~ThreadPersistentIdentityScope();
  ThreadPersistentIdentityScope(const ThreadPersistentIdentityScope &) = delete;
  ThreadPersistentIdentityScope &operator=(
      const ThreadPersistentIdentityScope &) = delete;
};

[[nodiscard]] const PersistentIdentity *
thread_persistent_identity() noexcept;

} // namespace uml::cpu::arm64
