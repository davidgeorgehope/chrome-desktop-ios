# Reuse one JitCompiler per executor and reserve emit buffers

A SIGPROF profile of official-from-main `uml-darwin` (hook-fix + 0011–0013
already in the tree) showed leftover cold-compile cost after packed
publish and the publish arena: `malloc` ~9% and `memmove` ~45% of the
compile window, with decode/emit still only ~1–4%. The earlier official-4K
profile (malloc ~35%, memmove ~25%) had already been partly cut by
0011–0013; those three remain promoted.

Each translated block used to construct a stack `JitCompiler`, whose
`Arm64Emitter` vectors (`words_`, labels, patches, relocs) grew with
`realloc` and were then `memcpy`'d into the executable arena. This patch:

1. Allocates one `JitCompiler` per executor (`std::unique_ptr` at the
   **end** of `Implementation`, so a side-link against older objects does
   not shift `Tlb` or the arenas). Putting it between the arenas and
   `Tlb` is an ABI break and panics `/init` (`Event::fatal` at
   `0x400444`, `exitcode=0x0000000b`) when mixed with pre-patch objects.
2. Rebinds resolvers with `configure()` so the same instance also serves
   tracked-store and single-instruction compiles.
3. Calls `begin_translation()` at the start of `compile_once` to reset
   per-block flags, register-cache slots, and emitter vectors, while
   **keeping vector capacity** (`words_` reserved to at least 2048).

Host words are still copied into the code cache by `store_block` and
packed publish. Emitting straight into a reserved writable arena window
was not landed here; the leftover `memmove` in the compile window is
largely that copy.

Persist stays **off** unless the directory env is set. Nothing in this
patch enables it. Do not turn persist on for Designed-for-iPad until the
openssl 8192-byte hang is shown safe.

See NOTES.md for the official-c134a87 vs `uml-darwin-alloc` table
(Firefox TTP, compile-cold, evp, SIGPROF). Apply from the Kernarium tree
with `python3 patches/0021-jit-compile-reuse/apply.py` after 0020. The
iPhoneSimulator 26.5 SDK also needs `patches/0014-simulator-vm-region-64`.
Do not install the resulting app on a physical iPhone. Do not overwrite
the frozen official copies `uml-darwin-official-c134a87` /
`uml-darwin-official-20261113`.
