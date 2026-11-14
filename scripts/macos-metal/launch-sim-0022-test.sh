#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export LANG=C
TAG="${1:-ff}"
ROOTFS_NAME="${2:-alpine-3.24.2-desktop-labwc.ext4}"
K=/Users/davidhope/linux-ios-bakeoff/src/Kernarium-0022-clean
NOTES=/Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop
UDID=8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$NOTES/kernarium-sim-0022-$TAG-session-$STAMP.log"
MEMLOG="$NOTES/kernarium-sim-0022-$TAG-memory-$STAMP.log"
XC_LOG="$NOTES/kernarium-sim-0022-$TAG-xcodebuild-$STAMP.log"
mkdir -p "$NOTES"

export UML_PREFLIGHT_GUEST_MEM=4G
. "$NOTES/preflight-uml-darwin.sh"

unset UML_JIT_PERSISTENT_CACHE KERNARIUM_JIT_PERSISTENT_CACHE \
  UML_JIT_PERSISTENT_CACHE_SOURCE KERNARIUM_JIT_PERSISTENT_CACHE_SOURCE || true

export TEST_RUNNER_KERNARIUM_DISPLAY_HEIGHT=1080
export TEST_RUNNER_KERNARIUM_DISPLAY_WIDTH=1920
# GUEST_MIB=3072 for the phone profile (see NOTES, 13 Nov 9:10 PM ET).
export TEST_RUNNER_KERNARIUM_GUEST_MEMORY_MIB="${GUEST_MIB:-4096}"
export TEST_RUNNER_KERNARIUM_GUEST_SESSION=1
export TEST_RUNNER_KERNARIUM_GUEST_SESSION_BENCHES=1
export TEST_RUNNER_KERNARIUM_GUEST_SESSION_BENCH_DELAY=90
export TEST_RUNNER_KERNARIUM_GUEST_SESSION_LOG=guest-session.log
export TEST_RUNNER_KERNARIUM_GUEST_SESSION_NET_PROBE=1
export TEST_RUNNER_KERNARIUM_GUEST_SESSION_TIMEOUT=900
export TEST_RUNNER_KERNARIUM_ROOTFS="$ROOTFS_NAME"
export TEST_RUNNER_KERNARIUM_SERIAL_LOG=guest-serial.log
export TEST_RUNNER_KERNARIUM_VCPU_COUNT=8
export TEST_RUNNER_UML_JIT_SHARED_STATS=1
# JIT budget. The binary default (1 GiB at mem=4G) is consumed by the
# 8 private L1s, leaving a ~100 KiB shared tier that evicts every insert
# (13 Nov 8:01 PM ET: Chromium cold 23 s, scroll 1.9 fps). 4G/128M gives a
# 3 GiB shared tier (Chromium cold 9 s, scroll 17-18 fps). Override with
# JIT_BUDGET / JIT_EXECUTOR_BUDGET; JIT_BUDGET=default keeps the binary default.
JIT_BUDGET="${JIT_BUDGET:-4G}"
JIT_EXECUTOR_BUDGET="${JIT_EXECUTOR_BUDGET:-128M}"
if [ "$JIT_BUDGET" != default ]; then
  export TEST_RUNNER_KERNARIUM_JIT_CACHE_BUDGET="$JIT_BUDGET"
  export TEST_RUNNER_KERNARIUM_JIT_EXECUTOR_CACHE_BUDGET="$JIT_EXECUTOR_BUDGET"
fi

{
  echo "===== $(date) sim-0022 tag=$TAG rootfs=$ROOTFS_NAME (parallel=NO, 1 dest) pid=$$ ====="
  echo "root=$K"
  echo "persist env:"; env | grep PERSISTENT_CACHE || echo "(none)"
  echo "swap start:"; sysctl vm.swapusage
  env | grep TEST_RUNNER_ | sort
} | tee "$LOG"
echo "$LOG" > "$NOTES/sim-0022-session.path"
echo "$STAMP" > "$NOTES/sim-0022-session.stamp"

(
  echo "memory sampler sim-0022-$TAG $(date) start_swap=${UML_SWAP_USED_AT_START:-0}M" >"$MEMLOG"
  for i in $(seq 1 480); do
    date >>"$MEMLOG"
    swline=$(sysctl vm.swapusage)
    echo "$swline" >>"$MEMLOG"
    /bin/ps -axo pid,rss,comm 2>/dev/null | /usr/bin/awk '/Kernarium.app\/Kernarium|launchd_sim/ {print}' >>"$MEMLOG"
    echo "-----" >>"$MEMLOG"
    # SWAP_ABORT stays on even if UML_ALLOW_HEAVY was used to pass
    # start-of-run preflight (Peek iPhone 17 already holds ~12 GiB, so
    # the 4G+2G headroom gate cannot pass on the 16 GB mini).
    used=$(echo "$swline" | sed -n 's/.*used = \([0-9.][0-9.]*\)M.*/\1/p')
    used=${used:-0}
    start=${UML_SWAP_USED_AT_START:-0}
    awk -v u="$used" -v s="$start" 'BEGIN { exit (u+0 > s+0 + 2048) }' || {
      echo "SWAP_ABORT used=${used}M start=${start}M limit=+2048M $(date)" | tee -a "$MEMLOG"
      # Actually stop the guest: TERM, then KILL, the app process.
      /usr/bin/pkill -TERM -f 'Kernarium\.app/Kernarium' 2>/dev/null || true
      sleep 5
      /usr/bin/pkill -KILL -f 'Kernarium\.app/Kernarium' 2>/dev/null || true
      echo "SWAP_ABORT killed app $(date)" | tee -a "$MEMLOG"
      break
    }
    sleep 2
  done
) &
MEMPID=$!

set +e
/usr/bin/script -q "$LOG" /usr/bin/caffeinate -dims \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
    -project "$K/Kernarium/Kernarium.xcodeproj" \
    -scheme Kernarium \
    -configuration Release \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$K/.build/kernarium-simulator-derived" \
    -jobs 2 \
    -parallel-testing-enabled NO \
    -parallel-testing-worker-count 1 \
    -maximum-concurrent-test-simulator-destinations 1 \
    "-only-testing:KernariumTests/GuestSessionTests" \
    CODE_SIGNING_ALLOWED=NO \
    EXCLUDED_ARCHS=x86_64 \
    DEVELOPMENT_TEAM=4P2629648N \
    ENABLE_TESTABILITY=YES \
    test \
    >"$XC_LOG" 2>&1
XC=$?
set -e
echo "xcodebuild exit=$XC $(date)" | tee -a "$LOG"
echo "swap end:" | tee -a "$LOG"
sysctl vm.swapusage | tee -a "$LOG"
echo "LOG=$LOG MEMLOG=$MEMLOG XC_LOG=$XC_LOG" | tee -a "$LOG"
kill "$MEMPID" 2>/dev/null || true
wait "$MEMPID" 2>/dev/null || true

find /Users/davidhope/Library/Developer/XCTestDevices \
     /Users/davidhope/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Data/Application \
  \( -name 'guest-session.log' -o -name 'guest-serial.log' \) 2>/dev/null | while read f; do
    bn=$(basename "$(dirname "$f")")_$(basename "$f")
    cp -p "$f" "$NOTES/kernarium-sim-0022-$TAG-$bn" 2>/dev/null || true
    echo "copied $f" | tee -a "$LOG"
  done
exit "$XC"
