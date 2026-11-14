Harness for the Kernarium port work. Logs default to /tmp/k-harness (not scratch).
- prof-launch.sh + guest-prof.sh/guest-spawn.sh + phase-deltas.py: per-phase JIT counters and the SIGPROF histogram. Set KBIN; optional LOGDIR, MEM, NCPUS, SIGPROF, GUEST.
- cpu-ab.sh TAG BIN_A BIN_B: cmp-benches.sh A/B (gcc, node, python, awk, sha, spawn)
- k-measure.sh: the desktop browser gate (KBIN env)

- k-boot.sh TAG: boot-only smoke test (does /init mount devtmpfs?). Set KBIN.
  Optional UML_JIT_SHARED_PIC=1, MEM, NCPUS, TIMEOUT, LOGDIR (default /tmp/k-harness).
  Does not use scratch/jitprof.
