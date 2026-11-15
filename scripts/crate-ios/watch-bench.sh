#!/bin/bash
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
CLOG=/Users/davidhope/Library/Containers/FDD810C1-810B-4414-9FB7-3E506CE3509A/Data/Library/Caches/console.log
CRATELOG=/Users/davidhope/Library/Containers/FDD810C1-810B-4414-9FB7-3E506CE3509A/Data/Library/Caches/crate.log
SHOTDIR=/Users/davidhope/linux-ios-bakeoff/scratch/crate-ios-shots
MARK=/tmp/k-harness/logs/crate-bench-watch.log
mkdir -p "$SHOTDIR"
echo "WATCH_START $(date)" | tee "$MARK"
took_cr=0
last_shot=0
deadline=$((SECONDS + 3600))
while (( SECONDS < deadline )); do
  now=$(date +%H:%M:%S)
  if grep -q '===BENCH_DONE===' "$CLOG" 2>/dev/null; then
    echo "$now BENCH_DONE" | tee -a "$MARK"
    screencapture -x -l $(osascript -e 'tell app "Crate" to id of window 1' 2>/dev/null) "$SHOTDIR/d4-bench-done.png" 2>/dev/null \
      || screencapture -x "$SHOTDIR/d4-bench-done.png"
    echo WATCH_OK
    exit 0
  fi
  # Chromium linger: first chromium launch marker or cr-1
  if (( took_cr == 0 )) && grep -E '===CHROMIUM_|tag=cr-1|INTERACTIVE_LAUNCH|chromium cr-1' "$CLOG" >/dev/null 2>&1; then
    # a couple of extra seconds so the window is painted
    sleep 2
    screencapture -x "$SHOTDIR/d4-chromium.png"
    echo "$now SHOT_CHROMIUM $SHOTDIR/d4-chromium.png" | tee -a "$MARK"
    took_cr=1
  fi
  # periodic screenshot every 120s until chromium
  if (( took_cr == 0 )) && (( SECONDS - last_shot >= 120 )); then
    screencapture -x "$SHOTDIR/d4-progress-$(date +%H%M%S).png"
    echo "$now SHOT_PROGRESS" | tee -a "$MARK"
    last_shot=$SECONDS
  fi
  # crash / fatal
  if grep -q 'Fatal error' /tmp/k-harness/logs/crate-ios-d4-brk69.log 2>/dev/null; then
    echo "$now FATAL in lldb log" | tee -a "$MARK"
    screencapture -x "$SHOTDIR/d4-fatal.png"
    exit 2
  fi
  if ! pgrep -x Crate >/dev/null; then
    echo "$now Crate exited" | tee -a "$MARK"
    exit 3
  fi
  # heartbeat every 30s: last interesting console line
  if (( SECONDS % 30 == 0 )); then
    echo "$now heartbeat console=$(wc -c < "$CLOG") last=$(tail -1 "$CLOG" | tr -d '\r' | cut -c1-160)" | tee -a "$MARK"
    sleep 1
  fi
  sleep 1
done
echo "WATCH_TIMEOUT $(date)" | tee -a "$MARK"
screencapture -x "$SHOTDIR/d4-timeout.png"
exit 4
