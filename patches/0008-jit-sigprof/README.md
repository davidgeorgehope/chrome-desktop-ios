# 0008 — In-process SIGPROF host-PC histogram

A cheap sampler for `uml-darwin` when `dtrace` and `sample` are unavailable
(SIP / no `timeout` / TCC). Off unless `UML_JIT_SIGPROF` is set to `1` or a
dump path. Optional `UML_JIT_SIGPROF_FILE` and `UML_JIT_SIGPROF_HZ` (default
99). The handler only bumps preallocated atomics; symbolization happens at
dump time. JIT arenas are named so unsigned PCs print as `jit+offset`.

`darwin_uml_exit()` uses `_exit()`, which skips `atexit`, so the sampler also
dumps from that path (weak hook) and from a 1 s flusher when a dump file is
set.

Default off. No effect on official timings.
