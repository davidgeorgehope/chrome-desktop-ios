#!/bin/bash
# Usage: footprint-sampler.sh OUTPREFIX [seconds]
# Records phys_footprint (jetsam metric) every 5 s and a vmmap -summary
# region breakdown every 30 s for Kernarium.app/Kernarium. The app PID is
# re-resolved whenever the sampled process exits (the first launch after a
# runtime rebuild relaunches the app under a new PID), for up to
# REACQUIRE_S (default 300) seconds without any app process.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
OUT=$1; DUR=${2:-420}; REACQ=${REACQUIRE_S:-300}
app_pid() { pgrep -f 'Kernarium\.app/Kernarium' | sort -n | tail -1; }
T0=$(date +%s); PID=""; MISSING_SINCE=$T0
echo "sampler start=$(date) dur=$DUR reacquire=$REACQ" > $OUT.fp.log
while :; do
  t=$(( $(date +%s)-T0 )); [ $t -gt $DUR ] && break
  if [ -z "$PID" ] || ! kill -0 $PID 2>/dev/null; then
    NEW=$(app_pid)
    if [ -z "$NEW" ]; then
      [ $(( $(date +%s)-MISSING_SINCE )) -gt $REACQ ] && { echo "no app for ${REACQ}s at t=$t" >> $OUT.fp.log; break; }
      sleep 1; continue
    fi
    if [ "$NEW" != "$PID" ]; then
      PID=$NEW; echo "pid=$PID t=$t at=$(date +%H:%M:%S)" >> $OUT.fp.log
      [ -n "$FIRST_DONE" ] || { sleep ${FP_DELAY:-25}; FIRST_DONE=1; }  # let lldb jit_serve attach/detach
    fi
  fi
  MISSING_SINCE=$(date +%s)
  fp=$(footprint -p $PID 2>/dev/null | grep -E "Footprint|phys_footprint" | head -2 | tr '\n' ' ')
  rss=$(ps -o rss= -p $PID 2>/dev/null)
  [ -n "$fp" ] && echo "t=$t $(date +%H:%M:%S) pid=$PID rss_kb=$rss $fp" >> $OUT.fp.log
  if [ $((t % 30)) -lt 5 ]; then echo "=== t=$t $(date +%H:%M:%S) pid=$PID" >> $OUT.vmmap.log; vmmap -summary $PID 2>/dev/null | sed -n '/^REGION TYPE/,/^TOTAL/p' >> $OUT.vmmap.log; fi
  sleep 5
done
echo "end=$(date)" >> $OUT.fp.log
