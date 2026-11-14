#!/bin/bash
# Usage: run-sim-interactive.sh TAG ROOTFS [JIT_BUDGET JIT_EXECUTOR_BUDGET]
# One Simulator GuestSessionTests run on Peek (parallel=NO, one destination)
# via launch-sim-0022-test.sh, then a parse-ios-interactive.py summary.
# Peek must already be Booted; UML_ALLOW_HEAVY=1 only passes the start
# preflight (Peek holds GBs); SWAP_ABORT in the launcher stays on.
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
TAG=$1; ROOTFS=$2
D=/Users/davidhope/linux-ios-bakeoff/notes/ios-interactive
N=/Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop
if pgrep -f '[u]ml-darwin|[x]codebuild' >/dev/null; then echo "refuse: overlap"; exit 2; fi
[ -n "${3:-}" ] && export JIT_BUDGET=$3
[ -n "${4:-}" ] && export JIT_EXECUTOR_BUDGET=$4
echo "RUN_START $(date) tag=$TAG jit=${JIT_BUDGET:-default}/${JIT_EXECUTOR_BUDGET:-default}"
UML_ALLOW_HEAVY=1 $N/launch-sim-0022-test.sh "$TAG" "$ROOTFS" > $D/sim-$TAG.launch.out 2>&1; rc=$?
echo "RUN_END $(date) exit=$rc"
ser=$(ls -t $N/kernarium-sim-0022-$TAG-*guest-serial.log 2>/dev/null | head -1)
ses=$(ls -t $N/kernarium-sim-0022-$TAG-session-*.log | head -1)
mm=$(ls -t $N/kernarium-sim-0022-$TAG-memory-*.log | head -1)
echo "SERIAL=$ser"
python3 $D/parse-ios-interactive.py "$ser" "$ses" "$mm"
grep -a SWAP_ABORT "$mm" | tail -2
