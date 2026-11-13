Shared-translation publication for uml-darwin (12 Nov 2026).

Apply on top of `0006-jit-direct-and-indirect-links`. The `.patch` file is the incremental diff for files that already had a 0006 copy (`jit_emitter`, `jit_exit_profile`) plus the `options.cpp` default-budget hunk. The other files in this directory (`jit_shared_translations.cpp/.hpp`, tests, test support, full `options.cpp`) are complete sources as landed.

What changed:
- Out-of-range *relocatable* link literals use a nearby LDR island, not a host-baked MOV-wide stub. `load_stable_pointer` still uses MOV-wide when the pool is out of reach.
- `SharedTranslationCache` publishes with one live executor and accepts up to `maximum_block_instructions` relocations.
- Default `--jit-cache-budget` is `guest/2 + 256 MiB * ncpus + 1 GiB` so the shared cache has a 2 GiB leftover at `mem=2G ncpus=8`.
- The exit profiler dumps shared rejected/malformed reasons and accounted vs maximum bytes.

Verified on the official macOS `uml-darwin` JIT, profiler off: compile tiny-sha 1.87 s cold / 1.09 s warm (was 2.92 s), dash 20k 0.19 s (was 0.24 s), gcc native-loop 0.49 s (was 0.57 s). See `scripts/cpu-benches/RESULTS.md`.
