#!/usr/bin/env python3
# phase-deltas.py PROFDIR : per-phase deltas of UML_JIT_PROFILE counters
# (dump at each ===PHASE=== start).
import sys, re, os

d = sys.argv[1]
ph = [l.split()[2] for l in open(f"{d}/phases.txt") if "===PHASE===" in l]
T = {}
for l in open(f"{d}/phases.txt"):
    m = re.search(r"===T=== (\S+) ([0-9.]+)", l)
    if m:
        T[m.group(1)] = float(m.group(2))

def rd(p):
    v = {}
    try:
        for l in open(p):
            if "=" in l and not l.startswith("==="):
                k, x = l.strip().split("=", 1)
                try:
                    v[k] = float(x)
                except ValueError:
                    pass
    except FileNotFoundError:
        return None
    return v

keys = [
    "compiles", "compile_ms", "shared_reuse", "shared.misses",
    "cache_miss", "cache_hit", "retired_insns",
    "exit.svc", "exit.page_fault",
    "exit.indirect_miss",
    "exit.indirect_miss.ret", "exit.indirect_miss.blr", "exit.indirect_miss.br",
    "exit.continued",
    "exit.continued.uncompiled", "exit.continued.no_link",
    "exit.continued.unsafe", "exit.continued.inactive",
    "exit.continued.selector_store", "exit.continued.selector_fp",
    "exit.continued.fairness", "exit.continued.nonlink",
    "run_blocks",
]

wide = os.environ.get("PHASE_WIDE", "0") == "1"
if not wide:
    # compact default for a first look; full table with PHASE_WIDE=1
    keys = [
        "compiles", "compile_ms", "retired_insns", "run_blocks",
        "exit.svc", "exit.page_fault", "exit.indirect_miss",
        "exit.indirect_miss.ret", "exit.indirect_miss.blr", "exit.indirect_miss.br",
        "exit.continued",
        "exit.continued.uncompiled", "exit.continued.fairness",
        "exit.continued.nonlink", "exit.continued.unsafe",
        "exit.continued.inactive", "exit.continued.no_link",
        "exit.continued.selector_store", "exit.continued.selector_fp",
    ]

short = lambda k: k.replace("exit.indirect_miss", "ind").replace("exit.continued", "cont").replace("exit.", "e.")
print("%-28s %6s " % ("phase", "wall") + " ".join("%11s" % short(k) for k in keys))
for a, b in zip(ph, ph[1:]):
    A, B = rd(f"{d}/at-{a}.txt"), rd(f"{d}/at-{b}.txt")
    if not A or not B:
        continue
    print("%-28s %6.2f " % (a, T.get(a, 0)) + " ".join("%11.0f" % (B.get(k, 0) - A.get(k, 0)) for k in keys))
