# 0010 — Raise the shared-translation relocation cap above 64

After file+offset keys (`0009`), a shared translation can carry more
relocatable slots than guest instructions: each ADR/ADRP may need a
guest-PC literal, and the block still has exit slots (`store_pc`, LR,
the indirect-site key, taken/fallthrough links). The cap of
`maximum_block_instructions` (64) rejected 8,909 unique gcc publications
(`shared.malformed.reloc_count`).

The cap is now `maximum_block_instructions * 2 + 4` (132). The installer's
`relocated_link_pointers_` scratch is reserved to that cap (it is a
growable `std::vector`). `store_block`'s `missing_keys` array is still
`maximum_block_instructions+1` and only counts unique direct-link keys.

Official-like timings, profiler off, ASLR left on:

- `sh_loop_dash` (20k): 0.18 s (unchanged)
- `compile_tiny_sha` cold: 2.07 s (was 2.12 s)
- `compile_tiny_sha` warm: 1.16 s (was 1.22 s)

A profiled compile (boot+apk+cold+warm) showed
`shared.malformed.reloc_count=0`, `shared.malformed_rejected=0`,
`shared.reuses=507,010`, `shared.insertions=172,899`, `compile_ms=683`
(was 814 with the 8,909 rejects). Tight gcc loop, evp, and tiny-sha-run
were re-timed in a full ASLR-on suite and did not regress (native loop
still 0.49 s / 1.26×; tiny-sha-run 1.182 s / 81.22 MiB/s, within noise
of 1.179 s / 81.42 MiB/s).
