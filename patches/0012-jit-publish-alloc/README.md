# Cut cold-translation publication cost

A SIGPROF histogram at 999 Hz on official 4K `uml-darwin`, isolated to the
`compile_tiny_sha` window (cumulative dump just before the compile minus
the dump at exit), shows that decode/emit/`compile_once` are not the
8.6× cold-compile tax:

| bucket | official compile window |
| --- | ---: |
| host malloc | 34.7% (`_xzm_xzone_malloc_freelist_outlined` 31%) |
| host memmove/memset | 24.8% |
| JIT generated code (gcc running) | 12.0% — about 0.25 s of a 2.08 s compile, i.e. almost native |
| shared-cache find / `valid_shared_translation_shape` | 11.5% (the shape walk alone 6.0%) |
| decode + emit + `compile_once` | 3.7% |
| link table + icache/W^X + arena store | ~5.6% |
| shared-cache insert lock | 0.1% |

Lock contention across 8 vCPUs is not the problem. A cheaper first-tier
1:1 emit would not help much. Block size cannot go past 64 because the
memory-write mask is a `uint64_t`. The cost is allocating and copying
each published `SharedTranslation` (object + two `vector` buffers +
guest-word array, plus hash-map growth) and walking the publication
shape twice.

This patch, on top of evict-on-full (0011):

1. Packs guest identity, host words, and relocations into one payload
   owned by an aliasing `guest_words` shared_ptr. `words` and
   `relocations` are spans into that payload. Publication drops from
   four heap hits to two (the `SharedTranslation` object and the pack).
2. Stops calling `valid_shared_translation_shape` at the end of
   `insert()` after the same checks have already run.
3. Pre-sizes each shard map (32,768) and the location index (2^18) so
   a cold gcc or libxul fill does not rehash from empty.

Measured on a side `uml-darwin-fast` (official 4K inode unchanged,
profilers off):

| | official 4K | packed-publish |
| --- | ---: | ---: |
| compile-cold (two runs) | 2.06 / 2.07 s | 1.96 / 1.98 s |
| apk add (same boots) | 2.80 / 2.81 s | 2.81 / 2.81 s |
| Firefox Isolated Web Content after READY | 12.27 s | 11.93 s |

The compile-window SIGPROF after the change drops the duplicate shape
walk to 0 and malloc samples 566 → 466. The official identity was not
bumped: this is a verified compile-cold win of about 5%, not a clean
full-suite promotion of the official 4K binary. Evict-on-full (0011)
was also compared same-session against official 4K and is within noise
(no regression, also not a suite wall-time win), so the official binary
stays at identity v26 / `0x1d7ce579d497fc37`.
