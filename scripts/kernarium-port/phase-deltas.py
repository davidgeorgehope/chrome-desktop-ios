#!/usr/bin/env python3
# phase-deltas.py PROFDIR : per-phase deltas of UML_JIT_PROFILE counters (dump at each ===PHASE=== start).
import sys, re, os
d = sys.argv[1]
ph = [l.split()[2] for l in open(f"{d}/phases.txt") if "===PHASE===" in l]
T = {}
for l in open(f"{d}/phases.txt"):
    m = re.search(r"===T=== (\S+) ([0-9.]+)", l)
    if m: T[m.group(1)] = float(m.group(2))
def rd(p):
    v = {}
    try:
        for l in open(p):
            if "=" in l and not l.startswith("==="):
                k, x = l.strip().split("=", 1)
                try: v[k] = float(x)
                except: pass
    except FileNotFoundError: return None
    return v
keys = ["compiles", "compile_ms", "shared_reuse", "shared.misses", "cache_miss", "cache_hit", "retired_insns", "exit.svc", "exit.page_fault", "exit.indirect_miss", "exit.continued"]
print("%-28s %6s " % ("phase", "wall") + " ".join("%12s" % k.replace("shared.", "sh.") for k in keys))
for a, b in zip(ph, ph[1:]):
    A, B = rd(f"{d}/at-{a}.txt"), rd(f"{d}/at-{b}.txt")
    if not A or not B: continue
    print("%-28s %6.2f " % (a, T.get(a, 0)) + " ".join("%12.0f" % (B.get(k, 0) - A.get(k, 0)) for k in keys))
