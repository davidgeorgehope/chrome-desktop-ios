# Designed-for-iPad JIT cache budget and debugger-region size

The default JIT budget on a process with a memory limit is the gadget
cache cap (272 MiB at 8 vCPUs), not one quarter of guest RAM. That 272 MiB
is almost entirely consumed by private L1s, leaving a ~105 KiB shared
translation cache (`accounted`/`max` ≈ 105792) that evicts on every insert.

Raising only `KERNARIUM_JIT_CACHE_BUDGET` is not enough:

- With the default 256 MiB per-executor cap, a 2 GiB whole-process budget
  still funds 8×256 MiB L1s and leaves the shared tier at the 64 KiB floor.
- The debugger-blessed executable region (L1 arenas only) was also hard-capped
  at 1 GiB (`region_limit` in `executable_memory.cpp`). A 2 GiB budget with
  the 256 MiB L1 cap asks for a ~1.2 GiB region and fails before `brk #0xf00d`
  (`the executable memory could not be prepared`).

This change:

- Honors `KERNARIUM_JIT_EXECUTOR_CACHE_BUDGET`, then
  `UML_JIT_EXECUTOR_CACHE_BUDGET` (K/M/G suffix, at most 256 MiB) in
  `jit_executor_cache_budget_for()`, used by `prepare_jit_memory` and by
  `KernariumRuntime.mm` (which also passes `--jit-executor-cache-budget=` so
  the published pair matches).
- Raises `region_limit` to 2 GiB.
- Adds an optional `KERNARIUM_GUEST_SESSION_NET_PROBE=1` serial probe
  (resolv, route, `nslookup example.com`, ping 10.0.2.2, `wget` http://example.com)
  immediately after `===DESKTOP_READY===`.

On the 16 GiB bakeoff mini, use a 2 GiB whole-process budget and a 128 MiB
L1 cap so the shared tier gets ~1 GiB, and keep guest RAM at 4 GiB. That
stayed in RAM (no swap) on this host. Do not raise the budget to 4 GiB
here (an earlier Simulator 4 GiB run drove ~7.3 GiB of swap).

```
TEST_RUNNER_KERNARIUM_JIT_CACHE_BUDGET=2G
TEST_RUNNER_KERNARIUM_JIT_EXECUTOR_CACHE_BUDGET=128M
TEST_RUNNER_UML_JIT_SHARED_STATS=1
```

Apply `python3 patches/0019-debugger-jit-cache-budget/apply.py` from the
Kernarium tree after 0018, then rebuild the ios-device runtime with
`UML_IOS_DEBUGGER_JIT=ON` and package it. When attaching `lldb` + `jit_serve`,
also pass SIGUSR1/SIGUSR2/SIGALRM (UML uses them as IPIs); otherwise a
debugger that has not yet detached will stop on every signal.

Look for `execution engine jit (cache budget 2147483648 bytes, executor cap 134217728 bytes)`
and a `===JIT_SHARED_STATS===` line whose `max=` is ~1 GiB, not ~105 KiB.
Do not install this build on a physical iPhone.
