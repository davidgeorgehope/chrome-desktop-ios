#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export LANG=C
TAG="${1:-ff}"
ROOTFS_NAME="${2:-alpine-3.24.2-desktop-labwc.ext4}"
# Optional whole-process JIT budget / private L1 cap (default 4G / 128M since 13 Nov 7:40 PM ET; 2G thrashed the 1 GiB shared tier).
# The debugger-prepared executable region depends only on the L1 cap.
JIT_BUDGET="${3:-4G}"
JIT_EXECUTOR_BUDGET="${4:-128M}"
NOTES=/Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop
KERNARIUM=/Users/davidhope/linux-ios-bakeoff/src/Kernarium-0022-clean
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$NOTES/kernarium-ipad-0022-$TAG-session-$STAMP.log"
SERVE="$NOTES/kernarium-ipad-0022-$TAG-serve-$STAMP.log"
MEMLOG="$NOTES/kernarium-ipad-0022-$TAG-memory-$STAMP.log"
mkdir -p "$NOTES"

export UML_PREFLIGHT_GUEST_MEM=4G
. "$NOTES/preflight-uml-darwin.sh"

# Persist MUST stay off.
unset UML_JIT_PERSISTENT_CACHE KERNARIUM_JIT_PERSISTENT_CACHE \
  UML_JIT_PERSISTENT_CACHE_SOURCE KERNARIUM_JIT_PERSISTENT_CACHE_SOURCE \
  TEST_RUNNER_UML_JIT_PERSISTENT_CACHE TEST_RUNNER_KERNARIUM_JIT_PERSISTENT_CACHE \
  TEST_RUNNER_UML_JIT_PERSISTENT_CACHE_SOURCE TEST_RUNNER_KERNARIUM_JIT_PERSISTENT_CACHE_SOURCE \
  || true

export TEST_RUNNER_KERNARIUM_DISPLAY_HEIGHT=1080
export TEST_RUNNER_KERNARIUM_DISPLAY_WIDTH=1920
export TEST_RUNNER_KERNARIUM_GUEST_MEMORY_MIB=4096
export TEST_RUNNER_KERNARIUM_GUEST_SESSION=1
export TEST_RUNNER_KERNARIUM_GUEST_SESSION_BENCHES=1
export TEST_RUNNER_KERNARIUM_GUEST_SESSION_BENCH_DELAY=90
export TEST_RUNNER_KERNARIUM_GUEST_SESSION_LOG=guest-session.log
export TEST_RUNNER_KERNARIUM_GUEST_SESSION_NET_PROBE=1
export TEST_RUNNER_KERNARIUM_GUEST_SESSION_TIMEOUT=900
export TEST_RUNNER_KERNARIUM_JIT_CACHE_BUDGET="$JIT_BUDGET"
export TEST_RUNNER_KERNARIUM_JIT_EXECUTOR_CACHE_BUDGET="$JIT_EXECUTOR_BUDGET"
export TEST_RUNNER_KERNARIUM_ROOTFS="$ROOTFS_NAME"
export TEST_RUNNER_KERNARIUM_SERIAL_LOG=guest-serial.log
export TEST_RUNNER_KERNARIUM_VCPU_COUNT=8
export TEST_RUNNER_KERNARIUM_WAIT_FOR_DEBUGGER=1
export TEST_RUNNER_KERNARIUM_WAIT_FOR_DEBUGGER_TIMEOUT=300
export TEST_RUNNER_UML_JIT_SHARED_STATS=1

{
  echo "===== $(date) d4ipad-0022 tag=$TAG rootfs=$ROOTFS_NAME guest session start pid=$$ ====="
  echo "root=$KERNARIUM"
  echo "persist env (should be empty):"
  env | grep -E 'PERSISTENT_CACHE' || echo "(none)"
  echo "env:"
  env | grep -E 'TEST_RUNNER_.*(JIT|WAIT|ROOTFS|SESSION|DISPLAY|VCPU|GUEST_MEMORY)' | sort
  sysctl vm.swapusage
} | tee -a "$LOG"

(
  echo "memory sampler $TAG $(date) start_swap=${UML_SWAP_USED_AT_START:-0}M" >"$MEMLOG"
  for i in $(seq 1 480); do
    date >>"$MEMLOG"
    swline=$(sysctl vm.swapusage)
    echo "$swline" >>"$MEMLOG"
    ps -axo rss,pid,comm | awk 'tolower($3)~/(kernarium|xcodebuild)/ {print}' >>"$MEMLOG"
    echo "-----" >>"$MEMLOG"
    if [ "${UML_ALLOW_HEAVY:-0}" != 1 ]; then
      used=$(echo "$swline" | sed -n 's/.*used = \([0-9.][0-9.]*\)M.*/\1/p')
      used=${used:-0}
      start=${UML_SWAP_USED_AT_START:-0}
      awk -v u="$used" -v s="$start" 'BEGIN { exit (u+0 > s+0 + 2048) }' || {
        echo "SWAP_ABORT used=${used}M start=${start}M limit=+2048M $(date)" | tee -a "$MEMLOG"
        /usr/bin/pgrep -lf '[Kk]ernarium|[Xx]codebuild' >>"$MEMLOG" 2>/dev/null || true
        # Actually stop the guest: TERM, then KILL, the app process.
        /usr/bin/pkill -TERM -f 'Kernarium\.app/Kernarium' 2>/dev/null || true
        sleep 5
        /usr/bin/pkill -KILL -f 'Kernarium\.app/Kernarium' 2>/dev/null || true
        echo "SWAP_ABORT killed app $(date)" | tee -a "$MEMLOG"
        break
      }
    fi
    sleep 2
  done
) &
MEMPID=$!

WLOG="${LOG%.log}-lldb-waiter.log"
(
  echo "===== $(date) lldb waiter start =====" | tee -a "$WLOG"
  PID=""
  for i in $(seq 1 1200); do
    PID=$(pgrep -x Kernarium | head -1 || true)
    if [ -n "$PID" ]; then
      break
    fi
    sleep 0.25
  done
  if [ -z "$PID" ]; then
    echo "lldb waiter: no Kernarium pid after 300s $(date)" | tee -a "$WLOG"
    exit 1
  fi
  echo "lldb waiter attaching pid=$PID $(date)" | tee -a "$WLOG"
  /usr/bin/lldb -b \
    -o "settings set auto-confirm true" \
    -o "process attach --pid $PID" \
    -o "process handle SIGUSR1 -n true -p true -s false" \
    -o "process handle SIGUSR2 -n true -p true -s false" \
    -o "process handle SIGALRM -n true -p true -s false" \
    -o "command script import $KERNARIUM/tests/integration/support/ios_jit_debugger.py" \
    -o "jit_serve --log $SERVE --timeout 900" \
    >>"$WLOG" 2>&1
  echo "lldb waiter done $(date) serve_log=$SERVE" | tee -a "$WLOG"
) &
WAITPID=$!
echo "lldb waiter pid=$WAITPID" | tee -a "$LOG"

echo "$LOG" > "$NOTES/d4ipad-0022-current-session.path"
echo "$STAMP" > "$NOTES/d4ipad-0022-current-session.stamp"

XC_LOG="$NOTES/kernarium-ipad-0022-$TAG-xcodebuild-$STAMP.log"
set +e
/usr/bin/script -q "$LOG" /usr/bin/caffeinate -dims \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
    -project "$KERNARIUM/Kernarium/Kernarium.xcodeproj" \
    -scheme Kernarium \
    -configuration Release \
    -destination "platform=macOS,variant=Designed for iPad" \
    -derivedDataPath "$KERNARIUM/.build/kernarium-xcode-derived" \
    -jobs 4 \
    -parallel-testing-enabled NO \
    "-only-testing:KernariumTests/GuestSessionTests" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM=4P2629648N \
    ENABLE_TESTABILITY=YES \
    test \
    >"$XC_LOG" 2>&1
XC=$?
set -e
echo "xcodebuild exit=$XC $(date) tag=$TAG" | tee -a "$LOG"
echo "LOG=$LOG" | tee -a "$LOG"
echo "MEMLOG=$MEMLOG" | tee -a "$LOG"
echo "XC_LOG=$XC_LOG" | tee -a "$LOG"
kill "$MEMPID" "$WAITPID" 2>/dev/null || true
wait "$MEMPID" "$WAITPID" 2>/dev/null || true
echo "$XC" > "$NOTES/d4ipad-0022-last-exit.txt"
exit "$XC"
