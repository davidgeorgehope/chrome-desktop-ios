#!/bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
set -u
TAG="${1:-ff}"
UDID=8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB
SHOTDIR="/Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop/persist-ttp-sim-0022-${TAG}-manual"
LIST=/Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop/list-windows
mkdir -p "$SHOTDIR"
LOG="$SHOTDIR/watch.log"
echo "WATCH_START $(date) udid=$UDID tag=$TAG" | tee -a "$LOG"
# Wait for the simulator/app, then shoot for 4 minutes.
for i in $(seq 1 600); do
  stamp=$(date +%H%M%S)
  if xcrun simctl io "$UDID" screenshot "$SHOTDIR/t-${stamp}-io.png" 2>>"$LOG"; then
    echo "WINDOW_SEEN $(date) via simctl after ${i}s" | tee -a "$LOG"
    break
  fi
  lines=$("$LIST" 2>/dev/null || true)
  cand=$(echo "$lines" | awk '/Simulator|Kernarium/ {print $1; exit}' | sed 's/wid=//')
  if [ -n "$cand" ]; then
    /usr/sbin/screencapture -x -l "$cand" "$SHOTDIR/t-${stamp}-w${cand}.png" 2>>"$LOG" || true
    if [ -f "$SHOTDIR/t-${stamp}-w${cand}.png" ]; then
      echo "WINDOW_SEEN $(date) wid=$cand after ${i}s" | tee -a "$LOG"
      break
    fi
  fi
  if [ $((i % 10)) -eq 0 ]; then
    echo "waiting for sim shot t=${i}s $(date)" | tee -a "$LOG"
  fi
  sleep 1
done
for i in $(seq 1 240); do
  stamp=$(date +%H%M%S)
  xcrun simctl io "$UDID" screenshot "$SHOTDIR/t-${stamp}-io.png" 2>>"$LOG" || true
  sleep 1
done
echo "WATCH_END $(date)" | tee -a "$LOG"
