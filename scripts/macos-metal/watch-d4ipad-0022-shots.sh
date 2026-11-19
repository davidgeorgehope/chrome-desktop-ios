#!/bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
set -u
TAG="${1:-reuse}"
SHOTDIR="$HOME/linux-ios-bakeoff/notes/macos-metal-desktop/persist-ttp-d4ipad-0022-${TAG}-manual"
LIST=$HOME/linux-ios-bakeoff/notes/macos-metal-desktop/list-windows
mkdir -p "$SHOTDIR"
LOG="$SHOTDIR/watch.log"
echo "WATCH_START $(date)" | tee -a "$LOG"
wid=""
# Wait up to 10 minutes for the Kernarium window (xcodebuild may compile first).
for i in $(seq 1 600); do
  stamp=$(date +%H%M%S)
  lines=$("$LIST" 2>/dev/null || true)
  cand=$(echo "$lines" | awk '/owner=Kernarium/ {print $1; exit}' | sed 's/wid=//')
  if [ -z "$cand" ]; then
    cand=$(echo "$lines" | awk '/[Kk]ernarium/ {print $1; exit}' | sed 's/wid=//')
  fi
  if [ -n "$cand" ]; then
    wid="$cand"
    echo "WINDOW_SEEN $(date) wid=$wid after ${i}s" | tee -a "$LOG"
    break
  fi
  if [ $((i % 10)) -eq 0 ]; then
    echo "waiting for window t=${i}s $(date)" | tee -a "$LOG"
  fi
  sleep 1
done
if [ -z "$wid" ]; then
  echo "WATCH_FAIL no Kernarium window $(date)" | tee -a "$LOG"
  exit 1
fi
# 4 minutes of 1s shots covers READY through body paint (70s baseline) plus slack.
for i in $(seq 1 240); do
  stamp=$(date +%H%M%S)
  lines=$("$LIST" 2>/dev/null || true)
  echo "=== $stamp ===" >>"$LOG"
  echo "$lines" >>"$LOG"
  cand=$(echo "$lines" | awk '/owner=Kernarium/ {print $1; exit}' | sed 's/wid=//')
  if [ -z "$cand" ]; then
    cand=$(echo "$lines" | awk '/[Kk]ernarium/ {print $1; exit}' | sed 's/wid=//')
  fi
  if [ -n "$cand" ]; then
    wid="$cand"
  fi
  if [ -n "$wid" ]; then
    out="$SHOTDIR/t-${stamp}-w${wid}.png"
    /usr/sbin/screencapture -x -l "$wid" "$out" 2>>"$LOG" || true
    if [ -f "$out" ]; then ls -l "$out" >>"$LOG"; fi
  fi
  sleep 1
done
echo "WATCH_END $(date) last_wid=$wid" | tee -a "$LOG"
