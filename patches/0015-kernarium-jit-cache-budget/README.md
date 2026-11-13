# Simulator JIT cache budget override

The default cache budget is one quarter of guest RAM (`1 GiB` at `mem=4G`).
With 8 vCPUs and a 256 MiB L1 cap, that entire 1 GiB is consumed by the
private L1s and the shared translation cache is left at about 64–105 KiB.
Firefox content processes then cannot reuse the parent's libxul
translations: a 1 GiB Simulator boot evicted on every insert (~12.2 M
rejects, 184 reuses).

This change makes `jit_cache_budget_for()` honor `KERNARIUM_JIT_CACHE_BUDGET`,
then `UML_JIT_CACHE_BUDGET` (K/M/G suffix), so a Simulator launch can fund a
real shared tier (`SIMCTL_CHILD_KERNARIUM_JIT_CACHE_BUDGET=4G` yields 8×256 MiB
L1 plus a 2 GiB shared cache). Set `SIMCTL_CHILD_UML_JIT_SHARED_STATS=1` to
dump `===JIT_SHARED_STATS===` about once a second.

A 4 GiB budget does stop the reject storm (millions of reuses, only a few
thousand rejects), but the shared tier still fills about 11 s after boot —
before Web Content starts — so Firefox chrome/full-page times stay about
35 s / 80 s after `DESKTOP_READY`. On the 16 GiB bakeoff mini that budget
also drove ~7.3 GiB of swap. Do not raise it further on that host. Unset
the `SIMCTL_CHILD_*` variable after a 4G run; it persists in the shell.

Apply on a Kernarium checkout with:

```sh
patch -p1 -d /path/to/Kernarium --forward < \
  patches/0015-kernarium-jit-cache-budget/jit_cache_budget_for.patch
```

`scripts/build-kernarium-simulator.sh` applies this together with the 0013
JIT sources and the 0014 `vm_region_64` fix.

Do not rebuild the official macOS `uml-darwin` identity from this tree
after applying these sources.
