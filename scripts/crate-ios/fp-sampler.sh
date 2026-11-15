#!/bin/bash
# Sample phys_footprint of Crate every 2s (bytes and MiB).
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
LOG=${1:-/tmp/k-harness/logs/crate-fp.log}
: > "$LOG"
echo "FP_START $(date)" >> "$LOG"
while true; do
  pid=$(pgrep -x Crate | head -1 || true)
  if [ -n "$pid" ]; then
    out=$(/usr/bin/footprint -p "$pid" -f bytes --noCategories 2>/dev/null || true)
    fp_b=$(printf '%s\n' "$out" | awk '/phys_footprint:/{print $2; exit}')
    peak_b=$(printf '%s\n' "$out" | awk '/phys_footprint_peak:/{print $2; exit}')
    rss=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print $1}')
    if [ -n "${fp_b:-}" ]; then
      fp_mib=$(awk -v b="$fp_b" 'BEGIN{printf "%.1f", b/1048576}')
      peak_mib=$(awk -v b="${peak_b:-0}" 'BEGIN{printf "%.1f", b/1048576}')
    else
      fp_mib=na
      peak_mib=na
    fi
    echo "$(date +%H:%M:%S) pid=$pid phys_footprint_B=${fp_b:-na} phys_footprint_MiB=${fp_mib} peak_MiB=${peak_mib} rss_KB=${rss:-na}" >> "$LOG"
  else
    echo "$(date +%H:%M:%S) pid=none" >> "$LOG"
  fi
  sleep 2
done
