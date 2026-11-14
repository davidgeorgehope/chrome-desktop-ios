#!/bin/bash
# Usage: footprint-sampler.sh OUTPREFIX [seconds]
# Waits for Kernarium.app/Kernarium, then every 5 s records phys_footprint
# (jetsam metric) and every 30 s a vmmap -summary region breakdown.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
OUT=$1; DUR=${2:-420}
for i in $(seq 1 300); do PID=$(pgrep -f 'Kernarium\.app/Kernarium' | head -1); [ -n "$PID" ] && break; sleep 1; done
[ -z "$PID" ] && { echo "no pid" > $OUT.fp.log; exit 1; }
sleep ${FP_DELAY:-25}  # let lldb jit_serve attach/prepare/detach first
echo "pid=$PID start=$(date)" > $OUT.fp.log
T0=$(date +%s)
while kill -0 $PID 2>/dev/null; do
  t=$(( $(date +%s)-T0 )); [ $t -gt $DUR ] && break
  fp=$(footprint -p $PID 2>/dev/null | grep -E "Footprint|phys_footprint" | head -2 | tr '\n' ' ')
  rss=$(ps -o rss= -p $PID)
  echo "t=$t $(date +%H:%M:%S) rss_kb=$rss $fp" >> $OUT.fp.log
  if [ $((t % 30)) -lt 5 ]; then echo "=== t=$t $(date +%H:%M:%S)" >> $OUT.vmmap.log; vmmap -summary $PID 2>/dev/null | sed -n '/^REGION TYPE/,/^TOTAL/p' >> $OUT.vmmap.log; fi
  sleep 5
done
echo "end=$(date)" >> $OUT.fp.log
