# 0009 — File+offset shared translations under ASLR

Shared translations are still inserted under the same-VA `PC+words` key, and
also under the host code-page stamp (`MappedBacking` identity + version) plus
the guest page offset. That stamp is unique for one physical backing page for
the life of the mapping, so `libc` / `ld-musl` / the toolchain hit after
`exec` even when ASLR moved the VA.

Baked guest addresses (`store_pc`, ADR/ADRP, BL return, indirect-site keys)
are recorded as `JitRelocationKind::guest_pc` literals. On materialization,
every guest PC and direct/indirect translation key is slid by
`new_pc - recorded_pc`. Mode bits in `translation_key()` are preserved
because a file+offset hit requires a matching page offset, so the slide is
page-aligned.

A first boot that reused unsild ADRP literals segfaulted in `ld-musl`;
recording ADRP (and the other leftover PC literals) fixed it.

Official timings, profiler off, ASLR left on (`randomize_va_space=1`):

- `sh_loop_dash` (20k): 0.18 s (was 0.19 s with ASLR off; no regression)
- `compile_tiny_sha` cold: 2.12 s
- `compile_tiny_sha` warm: 1.22 s (previously a warm `cc1` under ASLR
  missed the PC+words key and looked like a cold compile)

A profiled compile (boot+apk+cold+warm) showed `shared.reuses=513,919`,
`shared.insertions=171,055`, `compile_ms=814`. 8,909 publications were
rejected for `reloc_count` (blocks now carry extra guest-PC slots; the cap
is still `maximum_block_instructions`). That leftover is why warm wall is
a little above the 1.09 s ASLR-off figure; it is still far below a cold
compile under ASLR.
