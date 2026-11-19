#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
WRAPPER=/private/tmp/k-harness/crate-ios-d4-derived/Build/Products/Debug-iphoneos/.XCInstall/Crate.app
LOG=/tmp/k-harness/logs/crate-d4-launch.log
echo "LAUNCH $(date)" | tee "$LOG"
if pgrep -f '[u]ml-darwin|[x]codebuild|[Kk]ernarium\.app/Kernarium' >/dev/null; then
  echo "refuse: overlap" | tee -a "$LOG"
  exit 2
fi
if xcrun simctl list devices 2>/dev/null | grep -q Booted; then
  echo "refuse: Simulator Booted" | tee -a "$LOG"
  exit 2
fi
if pgrep -x Crate >/dev/null; then
  echo "Crate already running" | tee -a "$LOG"
  exit 1
fi
: > /tmp/k-harness/logs/crate-ios-d4-brk69.log
: > /tmp/k-harness/logs/crate-ios-d4-lldb-waiter.log
CRATE_BRK69_LOG=/tmp/k-harness/logs/crate-ios-d4-brk69.log \
CRATE_BRK69_TIMEOUT=7200 \
/usr/bin/lldb -b -o "command script import /tmp/k-harness/crate_brk69_waitandserve.py" \
  >> /tmp/k-harness/logs/crate-ios-d4-lldb-waiter.log 2>&1 &
echo LLDB_PID=$! | tee -a "$LOG"
sleep 2
open "$WRAPPER"
echo OPEN_RC=$? | tee -a "$LOG"
# Truncate the crate log so a stale "jit: on" cannot match this launch.
CLOG=$HOME/Library/Containers/APP-CONTAINER-UUID/Data/Library/Caches/crate.log
: > "$CLOG"
# wait for a fresh claim, up to 90s
for i in $(seq 1 90); do
  if grep -q 'last launch died claiming' "$CLOG" 2>/dev/null; then
    echo "JIT_SKIPPED claiming flag $(date)" | tee -a "$LOG"
    exit 3
  fi
  if grep -q 'crate launched' "$CLOG" 2>/dev/null && grep -q 'jit: on,' "$CLOG" 2>/dev/null; then
    echo "JIT_ON $(date)" | tee -a "$LOG"
    grep -E 'crate launched|jit:' "$CLOG" | tee -a "$LOG"
    exit 0
  fi
  sleep 1
done
echo "JIT_TIMEOUT $(date)" | tee -a "$LOG"
cat "$CLOG" | tee -a "$LOG"
exit 4
