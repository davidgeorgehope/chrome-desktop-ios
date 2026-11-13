#!/usr/bin/env python3
"""Reuse one JitCompiler per executor and keep emit-buffer capacity.
Run from the Kernarium tree after 0020. Idempotent.

compiler_ is added at the *end* of Implementation so a side-link against
objects compiled without this member does not shift Tlb or the arenas.
"""
from pathlib import Path
import sys


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    if new in text and old not in text:
        print(f"{path}: {label} already applied")
        return
    if old not in text:
        sys.exit(f"{path}: missing hook for {label}")
    path.write_text(text.replace(old, new, 1))
    print(f"{path}: {label}")


def main() -> None:
    emitter_hpp = Path("darwin/cpu/arm64/jit/jit_emitter.hpp")
    emitter_cpp = Path("darwin/cpu/arm64/jit/jit_emitter.cpp")
    families_hpp = Path("darwin/cpu/arm64/jit/jit_compiler_families.hpp")
    families_cpp = Path("darwin/cpu/arm64/jit/jit_compiler_families.cpp")
    compiler_hpp = Path("darwin/cpu/arm64/jit/jit_compiler.hpp")
    compiler_cpp = Path("darwin/cpu/arm64/jit/jit_compiler.cpp")
    internal = Path("darwin/cpu/arm64/jit/jit_executor_internal.hpp")
    lifecycle = Path("darwin/cpu/arm64/jit/jit_executor_lifecycle.cpp")
    execution = Path("darwin/cpu/arm64/jit/jit_executor_execution.cpp")
    paths = (emitter_hpp, emitter_cpp, families_hpp, families_cpp,
             compiler_hpp, compiler_cpp, internal, lifecycle, execution)
    if not all(p.is_file() for p in paths):
        sys.exit("run from the Kernarium tree after 0020")

    replace_once(
        compiler_hpp,
        """    [[nodiscard]] std::vector<ColdPath>::const_iterator
    end() const noexcept {
      return paths_.end();
    }

  private:
""",
        """    [[nodiscard]] std::vector<ColdPath>::const_iterator
    end() const noexcept {
      return paths_.end();
    }

    void clear() noexcept { paths_.clear(); }

  private:
""",
        "ColdPaths::clear",
    )

    replace_once(
        emitter_hpp,
        "  [[nodiscard]] std::span<const std::uint32_t> finish();\n",
        "  [[nodiscard]] std::span<const std::uint32_t> finish();\n"
        "  /* Clear words/labels/patches/relocs but keep capacity so a reused\n"
        "   * emitter does not malloc or memmove-grow on the next block. */\n"
        "  void reset();\n",
        "emitter reset decl",
    )

    if "void Arm64Emitter::reset()" not in emitter_cpp.read_text():
        # Insert after the finish() definition's closing, or after emit() if
        # finish is later in the file. Prefer immediately after the ctor.
        text = emitter_cpp.read_text()
        needle = (
            "void Arm64Emitter::emit(std::uint32_t instruction) { "
            "words_.push_back(instruction); }\n"
        )
        addition = needle + (
            "\n"
            "void Arm64Emitter::reset() {\n"
            "    words_.clear();\n"
            "    labels_.clear();\n"
            "    patches_.clear();\n"
            "    literal_patches_.clear();\n"
            "    relocations_.clear();\n"
            "    if (words_.capacity() < 2048)\n"
            "      words_.reserve(2048);\n"
            "    if (labels_.capacity() < 64)\n"
            "      labels_.reserve(64);\n"
            "    if (patches_.capacity() < 64)\n"
            "      patches_.reserve(64);\n"
            "    if (literal_patches_.capacity() < 64)\n"
            "      literal_patches_.reserve(64);\n"
            "    if (relocations_.capacity() < 64)\n"
            "      relocations_.reserve(64);\n"
            "    relocatable_ = true;\n"
            "    executable_words_ = 0;\n"
            "    valid_ = true;\n"
            "  }\n"
        )
        if needle not in text:
            sys.exit(f"{emitter_cpp}: missing emit() hook")
        emitter_cpp.write_text(text.replace(needle, addition, 1))
        print(f"{emitter_cpp}: reset()")
    else:
        print(f"{emitter_cpp}: reset() already applied")

    replace_once(
        families_hpp,
        "  void begin_link_observation() noexcept;\n",
        "  void begin_link_observation() noexcept;\n"
        "  /* Reset per-translation register-cache and flag state, keeping\n"
        "   * configured resolvers, mode, and emitter attachments. */\n"
        "  void begin_translation() noexcept;\n",
        "families begin_translation decl",
    )

    if "JitCompilerFamilies::begin_translation()" not in families_cpp.read_text():
        text = families_cpp.read_text()
        needle = (
            "void JitCompilerFamilies::begin_link_observation() noexcept {\n"
            "  direct_link_refusals_ = 0;\n"
            "  indirect_link_refusals_ = 0;\n"
            "}\n"
        )
        addition = needle + (
            "\n"
            "void JitCompilerFamilies::begin_translation() noexcept {\n"
            "  begin_link_observation();\n"
            "  gpr_slots_ = {};\n"
            "  vector_slots_ = {};\n"
            "  exit_gpr_mask_ = 0;\n"
            "  exit_vector_mask_ = 0;\n"
            "  exit_gpr_mask_set_ = false;\n"
            "  exit_vector_mask_set_ = false;\n"
            "  guest_flags_state_ = GuestFlagsState::memory;\n"
            "}\n"
        )
        if needle not in text:
            sys.exit(f"{families_cpp}: missing begin_link_observation hook")
        families_cpp.write_text(text.replace(needle, addition, 1))
        print(f"{families_cpp}: begin_translation()")
    else:
        print(f"{families_cpp}: begin_translation() already applied")

    replace_once(
        compiler_hpp,
        "  Result compile(std::uint64_t guest_pc,\n"
        "                 std::span<const std::uint32_t> instructions);\n",
        "  Result compile(std::uint64_t guest_pc,\n"
        "                 std::span<const std::uint32_t> instructions);\n"
        "\n"
        "  /* Rebind resolvers and the direct-store tracking flag so one\n"
        "   * compiler instance can serve ordinary, tracked-store, and\n"
        "   * single-instruction compiles. */\n"
        "  void configure(void *link_context, LinkResolver link_resolver,\n"
        "                 bool track_direct_stores,\n"
        "                 IndirectLinkResolver indirect_link_resolver = nullptr);\n"
        "\n"
        "  /* Reset per-block buffers and flags, keeping vector capacity. */\n"
        "  void begin_translation();\n",
        "compiler configure/begin_translation decls",
    )

    if "void JitCompiler::configure(" not in compiler_cpp.read_text():
        text = compiler_cpp.read_text()
        needle = (
            "JitCompiler::Result JitCompiler::compile(std::uint64_t guest_pc,\n"
            "                 std::span<const std::uint32_t> instructions) {\n"
            "    return compile_once(guest_pc, instructions);\n"
            "  }\n"
        )
        addition = needle + (
            "\n"
            "void JitCompiler::configure(void *link_context, LinkResolver link_resolver,\n"
            "                            bool track_direct_stores,\n"
            "                            IndirectLinkResolver indirect_link_resolver) {\n"
            "    configured_link_context_ = link_context;\n"
            "    configured_link_resolver_ = link_resolver;\n"
            "    configured_indirect_link_resolver_ = indirect_link_resolver;\n"
            "    track_direct_stores_ = track_direct_stores;\n"
            "    attach_family_emitter(&emitter_, &native_fp_, !track_direct_stores_);\n"
            "    attach_link_resolver(link_context, link_resolver);\n"
            "    attach_indirect_link_resolver(link_context, indirect_link_resolver);\n"
            "  }\n"
            "\n"
            "void JitCompiler::begin_translation() {\n"
            "    JitCompilerFamilies::begin_translation();\n"
            "    emitter_.reset();\n"
            "    cold_.clear();\n"
            "    translation_cold_.clear();\n"
            "    run_straddles_.clear();\n"
            "    if (translation_cold_.capacity() < 16)\n"
            "      translation_cold_.reserve(16);\n"
            "    if (run_straddles_.capacity() < 8)\n"
            "      run_straddles_.reserve(8);\n"
            "    count_ = 0;\n"
            "    memory_write_mask_ = 0;\n"
            "    direct_memory_write_mask_ = 0;\n"
            "    terminated_ = false;\n"
            "    accesses_fp_state_ = false;\n"
            "    link_target_safe_ = true;\n"
            "    native_fp_ = false;\n"
            "    guest_illegal_ = false;\n"
            "  }\n"
        )
        if needle not in text:
            sys.exit(f"{compiler_cpp}: missing compile() hook")
        compiler_cpp.write_text(text.replace(needle, addition, 1))
        print(f"{compiler_cpp}: configure/begin_translation")
    else:
        print(f"{compiler_cpp}: configure already applied")

    replace_once(
        compiler_cpp,
        "    begin_link_observation();\n"
        "    /* A streaming translation never binds a host vector register: AdvSIMD\n",
        "    begin_translation();\n"
        "    /* A streaming translation never binds a host vector register: AdvSIMD\n",
        "compile_once starts with begin_translation",
    )

    replace_once(
        internal,
        '#include "jit_cache.hpp"\n',
        '#include "jit_cache.hpp"\n'
        '#include "jit_compiler.hpp"\n',
        "internal include",
    )
    replace_once(
        internal,
        "  ::uml::cpu::HostCapabilities host_capabilities_;\n"
        "};\n",
        "  ::uml::cpu::HostCapabilities host_capabilities_;\n"
        "  /* After every field official objects already layout, so a\n"
        "   * side-link against those objects does not shift Tlb or the\n"
        "   * arenas. */\n"
        "  std::unique_ptr<JitCompiler> compiler_;\n"
        "};\n",
        "compiler_ at end of Implementation",
    )

    replace_once(
        lifecycle,
        "  register_jit_store_participant(store_participant_);\n"
        "  SharedTranslationCache::instance().add_executor();\n",
        "  register_jit_store_participant(store_participant_);\n"
        "  compiler_ = std::make_unique<JitCompiler>(\n"
        "      this, &Implementation::resolve_block_link, false,\n"
        "      &Implementation::resolve_indirect_link);\n"
        "  SharedTranslationCache::instance().add_executor();\n",
        "construct reused compiler",
    )

    replace_once(
        execution,
        "      JitCompiler compiler{\n"
        "          this, &Implementation::resolve_block_link, false,\n"
        "          &Implementation::resolve_indirect_link\n"
        "      };\n"
        "      compiler.set_translation_mode(mode);\n"
        "      // Compile once on a miss. Speculatively lowering the whole block a\n"
        "      // second time for GPR residency delays cold multi-process workloads.\n"
        "      const auto compiled = compiler.compile(cpu.pc, fetched);\n",
        "      compiler_->configure(this, &Implementation::resolve_block_link, false,\n"
        "                           &Implementation::resolve_indirect_link);\n"
        "      compiler_->set_translation_mode(mode);\n"
        "      // Compile once on a miss. Speculatively lowering the whole block a\n"
        "      // second time for GPR residency delays cold multi-process workloads.\n"
        "      const auto compiled = compiler_->compile(cpu.pc, fetched);\n",
        "main miss reuses compiler_",
    )
    replace_once(
        execution,
        "          JitCompiler retry_compiler{\n"
        "              this, &Implementation::resolve_block_link, false,\n"
        "              &Implementation::resolve_indirect_link\n"
        "          };\n"
        "          retry_compiler.set_translation_mode(mode);\n"
        "          const auto retry_compiled = retry_compiler.compile(\n"
        "              cpu.pc, std::span{instructions}.first(count));\n",
        "          compiler_->configure(this, &Implementation::resolve_block_link,\n"
        "                               false, &Implementation::resolve_indirect_link);\n"
        "          compiler_->set_translation_mode(mode);\n"
        "          const auto retry_compiled = compiler_->compile(\n"
        "              cpu.pc, std::span{instructions}.first(count));\n",
        "retry reuses compiler_",
    )
    replace_once(
        execution,
        "  JitCompiler compiler{nullptr, nullptr, true};\n"
        "  compiler.set_translation_mode(translation_key_mode(block.key));\n"
        "  const auto compiled = compiler.compile(\n"
        "      translation_key_pc(block.key),\n"
        "      std::span{instructions}.first(block.instruction_count));\n",
        "  compiler_->configure(nullptr, nullptr, true);\n"
        "  compiler_->set_translation_mode(translation_key_mode(block.key));\n"
        "  const auto compiled = compiler_->compile(\n"
        "      translation_key_pc(block.key),\n"
        "      std::span{instructions}.first(block.instruction_count));\n",
        "tracked-store reuses compiler_",
    )
    replace_once(
        execution,
        "  JitCompiler compiler{nullptr, nullptr, track_direct_stores};\n"
        "  compiler.set_translation_mode(mode);\n"
        "  return store_single_translation(\n"
        "      compiler.compile(pc, std::span{&instruction, std::size_t{1}}));\n",
        "  compiler_->configure(nullptr, nullptr, track_direct_stores);\n"
        "  compiler_->set_translation_mode(mode);\n"
        "  return store_single_translation(\n"
        "      compiler_->compile(pc, std::span{&instruction, std::size_t{1}}));\n",
        "single-instruction reuses compiler_",
    )


if __name__ == "__main__":
    main()
