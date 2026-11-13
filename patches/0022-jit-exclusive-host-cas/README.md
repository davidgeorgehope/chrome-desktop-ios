# 0022 — drop the process-wide exclusive-phase wait

Apply after 0021, from the Kernarium tree:

```
git apply patches/0022-jit-exclusive-host-cas/0022-jit-exclusive-host-cas.patch
```

This is a three-file change only (`jit_semantic_memory.cpp`, `a32_execute.cpp`,
`jit_publication.hpp`). Production LDXR/STXR no longer enter
`JitExclusiveOperationScope`. They use a QEMU-style host CAS against the
per-vCPU monitor. Reservation tracking still runs while a reservation is
live; the phase wait remains for tests and any remaining fallback. ABA is
still invisible, as in QEMU. LSE CAS/LDADD already skipped the gate.

This 0022 is **not** the earlier emit-in-place experiment, which was measured
and not landed (see NOTES). Persist stays off.

Identity on the mini: `uml-darwin-0022-clean-20261113` /
`uml-darwin-official-0022-20261113`, md5 `6ea8180e05fc6736d32530811ba3c439`,
kernel local2. Do not overwrite the frozen c134a87 official copies
(`uml-darwin-official-c134a87` / `-20261113`, md5
`91afb4a7fc3037c87b782081029fac21`).
