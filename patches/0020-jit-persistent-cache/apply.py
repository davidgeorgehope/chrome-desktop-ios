#!/usr/bin/env python3
"""Add the persistent translation cache and hook it into the shared RAM cache.
Run from the Kernarium tree after 0019. Idempotent."""
from pathlib import Path
import shutil
import sys

HERE = Path(__file__).resolve().parent


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    if new in text:
        print(f"{path}: {label} already applied")
        return
    if old not in text:
        sys.exit(f"{path}: missing hook for {label}")
    path.write_text(text.replace(old, new, 1))
    print(f"{path}: {label}")


def main() -> None:
    hpp = Path("darwin/cpu/arm64/jit/jit_shared_translations.hpp")
    cpp = Path("darwin/cpu/arm64/jit/jit_shared_translations.cpp")
    exe = Path("darwin/cpu/arm64/jit/jit_executor_cache.cpp")
    cmake = Path("darwin/cpu/CMakeLists.txt")
    engine = Path("tests/unit/arm64/engine.cmake")
    if not all(p.is_file() for p in (hpp, cpp, exe, cmake, engine)):
        sys.exit("run from the Kernarium tree")

    shutil.copy(HERE / "jit_persistent_translations.hpp",
                "darwin/cpu/arm64/jit/jit_persistent_translations.hpp")
    shutil.copy(HERE / "jit_persistent_translations.cpp",
                "darwin/cpu/arm64/jit/jit_persistent_translations.cpp")
    shutil.copy(HERE / "arm64_jit_persistent_translation_cache_tests.cpp",
                "tests/unit/arm64/arm64_jit_persistent_translation_cache_tests.cpp")
    print("copied persistent translation sources")

    replace_once(
        cmake,
        "    arm64/jit/jit_shared_translations.cpp\n",
        "    arm64/jit/jit_shared_translations.cpp\n"
        "    arm64/jit/jit_persistent_translations.cpp\n",
        "cmake source",
    )
    replace_once(
        engine,
        "    foreach(JIT_CACHE_TEST IN ITEMS cache_geometry shared_translation_cache)\n",
        "    foreach(JIT_CACHE_TEST IN ITEMS cache_geometry shared_translation_cache "
        "persistent_translation_cache)\n",
        "unit test",
    )

    if "class PersistentTranslationStore;" not in hpp.read_text():
        text = hpp.read_text()
        needle = "namespace uml::cpu::arm64 {\n"
        if needle not in text:
            sys.exit("hpp: missing namespace")
        hpp.write_text(text.replace(
            needle,
            needle + "\nclass PersistentTranslationStore;\n\n",
            1,
        ))
        print(f"{hpp}: fwd decl")
    else:
        print(f"{hpp}: fwd decl already applied")

    replace_once(
        hpp,
        "  [[nodiscard]] static SharedTranslationCache &instance() noexcept;\n",
        "  [[nodiscard]] static SharedTranslationCache &instance() noexcept;\n"
        "\n"
        "  void attach_persistent_store(\n"
        "      std::shared_ptr<PersistentTranslationStore> store) noexcept;\n"
        "  [[nodiscard]] PersistentTranslationStore *\n"
        "  persistent_store() const noexcept;\n",
        "attach API",
    )
    replace_once(
        hpp,
        "  std::size_t shard_capacity_;\n"
        "  std::size_t maximum_accounted_bytes_;\n"
        "};\n",
        "  std::size_t shard_capacity_;\n"
        "  std::size_t maximum_accounted_bytes_;\n"
        "  std::shared_ptr<PersistentTranslationStore> persistent_store_;\n"
        "};\n",
        "store member",
    )

    replace_once(
        cpp,
        "#include \"jit_shared_translations.hpp\"\n",
        "#include \"jit_shared_translations.hpp\"\n"
        "#include \"jit_persistent_translations.hpp\"\n",
        "cpp include",
    )

    replace_once(
        cpp,
        "    maybe_dump_shared_translation_stats();\n"
        "    return located;\n"
        "  }\n"
        "  misses_.fetch_add(1, std::memory_order_relaxed);\n",
        "    maybe_dump_shared_translation_stats();\n"
        "    return located;\n"
        "  }\n"
        "  if (persistent_store_ != nullptr) {\n"
        "    if (const auto *identity = thread_persistent_identity()) {\n"
        "      if (auto loaded = persistent_store_->lookup(\n"
        "              profile, guest_pc, guest_words, *identity)) {\n"
        "        loaded->code_page_identity = code_page_identity;\n"
        "        loaded->code_page_version = code_page_version;\n"
        "        const auto unit = aarch32::isa_unit_bytes(\n"
        "            static_cast<aarch32::GuestIsa>(loaded->isa));\n"
        "        const auto elements =\n"
        "            (loaded->guest_word_count * unit + sizeof(std::uint32_t) - 1U) /\n"
        "            sizeof(std::uint32_t);\n"
        "        const auto prefix = guest_words.first(\n"
        "            elements == 0 || elements > guest_words.size()\n"
        "                ? guest_words.size()\n"
        "                : elements);\n"
        "        auto *self = const_cast<SharedTranslationCache *>(this);\n"
        "        if (auto admitted =\n"
        "                self->insert(profile, guest_pc, prefix, loaded);\n"
        "            admitted != nullptr) {\n"
        "          matches_.fetch_add(1, std::memory_order_relaxed);\n"
        "          location_matches_.fetch_add(1, std::memory_order_relaxed);\n"
        "          if (admitted->recorded_pc != guest_pc)\n"
        "            slide_hits_.fetch_add(1, std::memory_order_relaxed);\n"
        "          maybe_dump_shared_translation_stats();\n"
        "          return admitted;\n"
        "        }\n"
        "        matches_.fetch_add(1, std::memory_order_relaxed);\n"
        "        maybe_dump_shared_translation_stats();\n"
        "        return loaded;\n"
        "      }\n"
        "    }\n"
        "  }\n"
        "  misses_.fetch_add(1, std::memory_order_relaxed);\n",
        "find persist lookup",
    )

    replace_once(
        cpp,
        "  shard.index_credit -= budget_charge - additional_charge;\n"
        "  ++shard.count;\n"
        "  payload_bytes_.fetch_add(payload_bytes, std::memory_order_relaxed);\n"
        "  insertions_.fetch_add(1, std::memory_order_relaxed);\n"
        "  return translation;\n"
        "}\n",
        "  shard.index_credit -= budget_charge - additional_charge;\n"
        "  ++shard.count;\n"
        "  payload_bytes_.fetch_add(payload_bytes, std::memory_order_relaxed);\n"
        "  insertions_.fetch_add(1, std::memory_order_relaxed);\n"
        "  cache_lock.unlock();\n"
        "  if (persistent_store_ != nullptr) {\n"
        "    if (const auto *identity = thread_persistent_identity())\n"
        "      persistent_store_->remember(profile, *translation, *identity);\n"
        "  }\n"
        "  return translation;\n"
        "}\n",
        "insert persist remember",
    )

    replace_once(
        cpp,
        "  if (auto located = find_at_location(profile, guest_pc, guest_words,\n"
        "                                      code_page_identity, code_page_version);\n"
        "      located != nullptr)\n"
        "    return {.canonical = located, .may_construct = false};\n",
        "  if (auto located = find_at_location(profile, guest_pc, guest_words,\n"
        "                                      code_page_identity, code_page_version);\n"
        "      located != nullptr)\n"
        "    return {.canonical = located, .may_construct = false};\n"
        "  if (persistent_store_ != nullptr) {\n"
        "    if (const auto *identity = thread_persistent_identity()) {\n"
        "      if (auto loaded = persistent_store_->lookup(\n"
        "              profile, guest_pc, guest_words, *identity)) {\n"
        "        loaded->code_page_identity = code_page_identity;\n"
        "        loaded->code_page_version = code_page_version;\n"
        "        return {.canonical = loaded, .may_construct = false};\n"
        "      }\n"
        "    }\n"
        "  }\n",
        "preflight persist",
    )

    attach_impl = (
        "void SharedTranslationCache::attach_persistent_store(\n"
        "    std::shared_ptr<PersistentTranslationStore> store) noexcept {\n"
        "  persistent_store_ = std::move(store);\n"
        "}\n"
        "\n"
        "PersistentTranslationStore *\n"
        "SharedTranslationCache::persistent_store() const noexcept {\n"
        "  return persistent_store_.get();\n"
        "}\n"
        "\n"
    )
    replace_once(
        cpp,
        "SharedTranslationCache &SharedTranslationCache::instance() noexcept {",
        attach_impl +
        "SharedTranslationCache &SharedTranslationCache::instance() noexcept {",
        "attach methods",
    )
    replace_once(
        cpp,
        "  static auto *cache = new SharedTranslationCache{\n"
        "      unlimited_shard_entries,\n"
        "      jit_shared_translation_cache_budget()};\n"
        "  install_shared_stats_hook();\n"
        "  return *cache;\n",
        "  static auto *cache = new SharedTranslationCache{\n"
        "      unlimited_shard_entries,\n"
        "      jit_shared_translation_cache_budget()};\n"
        "  install_shared_stats_hook();\n"
        "  static std::once_flag persist_once;\n"
        "  std::call_once(persist_once, [] {\n"
        "    if (auto store = open_persistent_translation_store_from_environment()) {\n"
        "      cache->attach_persistent_store(store);\n"
        "      std::atexit([] {\n"
        "        if (auto *owned = cache->persistent_store())\n"
        "          owned->flush();\n"
        "      });\n"
        "    }\n"
        "  });\n"
        "  return *cache;\n",
        "instance persist",
    )
    if "#include <mutex>" not in cpp.read_text().split("std::once_flag")[0][-500:]:
        # mutex already included for locks; once_flag is in <mutex>
        pass

    replace_once(
        cpp,
        "          identity_zero_finds_.load(std::memory_order_relaxed)),\n"
        "          static_cast<unsigned long long>(\n"
        "              identity_nonzero_finds_.load(std::memory_order_relaxed)));\n",
        "          identity_zero_finds_.load(std::memory_order_relaxed)),\n"
        "          static_cast<unsigned long long>(\n"
        "              identity_nonzero_finds_.load(std::memory_order_relaxed)));\n"
        "  if (auto *store = SharedTranslationCache::instance().persistent_store()) {\n"
        "    const auto persist = store->statistics();\n"
        "    dprintf(STDERR_FILENO,\n"
        "            \"===JIT_PERSIST_STATS=== why=%s hits=%llu stores=%llu \"\n"
        "            \"rejected=%llu entries=%llu data=%llu\\n\",\n"
        "            why,\n"
        "            static_cast<unsigned long long>(persist.hits),\n"
        "            static_cast<unsigned long long>(persist.stores),\n"
        "            static_cast<unsigned long long>(persist.rejected),\n"
        "            static_cast<unsigned long long>(persist.entries),\n"
        "            static_cast<unsigned long long>(persist.data_bytes));\n"
        "  }\n",
        "persist stats dump",
    )

    exe_text = exe.read_text()
    if "jit_persistent_translations.hpp" not in exe_text:
        # Insert the include after the first include.
        first = exe_text.find('#include ')
        if first < 0:
            sys.exit("executor: no include")
        line_end = exe_text.find('\n', first)
        exe.write_text(
            exe_text[:line_end + 1]
            + '#include "jit_persistent_translations.hpp"\n'
            + exe_text[line_end + 1:]
        )
        print(f"{exe}: executor include")
    else:
        print(f"{exe}: executor include already applied")

    replace_once(
        exe,
        "[[nodiscard]] uml::memory::CodePageStamp\n"
        "code_page_location(StaticGuestMemory &memory, std::uint64_t pc) noexcept {\n"
        "  uml::memory::CodePageStamp stamp{};\n"
        "  const auto address = aarch32::key_fetch_address(pc);\n"
        "  (void)memory.code_page_stamp(address, nullptr, stamp);\n"
        "  return stamp;\n"
        "}\n",
        "[[nodiscard]] uml::memory::CodePageStamp\n"
        "code_page_location(StaticGuestMemory &memory, std::uint64_t pc) noexcept {\n"
        "  uml::memory::CodePageStamp stamp{};\n"
        "  const auto address = aarch32::key_fetch_address(pc);\n"
        "  (void)memory.code_page_stamp(address, nullptr, stamp);\n"
        "  return stamp;\n"
        "}\n"
        "\n"
        "[[nodiscard]] PersistentIdentity\n"
        "persistent_identity_for(StaticGuestMemory &memory, std::uint64_t pc) noexcept {\n"
        "  PersistentIdentity identity{};\n"
        "  const auto address = aarch32::key_fetch_address(pc) & ~(page_size - 1U);\n"
        "  std::array<std::byte, static_cast<std::size_t>(page_size)> page{};\n"
        "  if (memory.fetch(address, page)) {\n"
        "    identity.page_hash = persistent_content_hash(page);\n"
        "    identity.has_page_hash = true;\n"
        "  }\n"
        "  return identity;\n"
        "}\n",
        "executor page hash",
    )
    replace_once(
        exe,
        "  auto &cache = SharedTranslationCache::instance();\n"
        "  const auto location = code_page_location(memory, pc);\n"
        "  const auto translation = cache.find(shared_codegen_profile(mode), pc,\n"
        "                                      guest_words, location.identity,\n"
        "                                      location.version);\n",
        "  auto &cache = SharedTranslationCache::instance();\n"
        "  const auto location = code_page_location(memory, pc);\n"
        "  const ThreadPersistentIdentityScope persist_scope{\n"
        "      persistent_identity_for(memory, pc)};\n"
        "  const auto translation = cache.find(shared_codegen_profile(mode), pc,\n"
        "                                      guest_words, location.identity,\n"
        "                                      location.version);\n",
        "executor find identity",
    )
    replace_once(
        exe,
        "  auto &cache = SharedTranslationCache::instance();\n"
        "  if (!compiled.relocatable)\n"
        "    return nullptr;\n"
        "  const auto profile = shared_codegen_profile(mode);\n"
        "  const auto location = code_page_location(memory, pc);\n",
        "  auto &cache = SharedTranslationCache::instance();\n"
        "  if (!compiled.relocatable)\n"
        "    return nullptr;\n"
        "  const auto profile = shared_codegen_profile(mode);\n"
        "  const auto location = code_page_location(memory, pc);\n"
        "  const ThreadPersistentIdentityScope persist_scope{\n"
        "      persistent_identity_for(memory, pc)};\n",
        "executor publish identity",
    )

    # std::once_flag needs <mutex>, already included in shared cpp.
    print("apply finished")


if __name__ == "__main__":
    main()
