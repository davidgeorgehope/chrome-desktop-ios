#!/bin/sh
# Periodic spawn/CPU probe for the UML desktop Firefox start.
# Prints to ttyS0 so a host console log can attribute time to process
# spawn vs parent-only JIT vs content-process JIT.
up() { awk '{print $1}' /proc/uptime; }
i=0
while [ "$i" -lt 90 ]; do
  i=$((i + 1))
  {
    echo "===FF_PS=== up=$(up) load=$(cat /proc/loadavg 2>/dev/null)"
    for d in /proc/[0-9]*; do
      pid=${d#/proc/}
      comm=$(cat "$d/comm" 2>/dev/null) || continue
      cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
      case "$comm $cmd" in
        *firefox*|*Firefox*|*WebContent*|*Web\ Content*|*Isolated*|*RDD*|*forkserver*|*Socket\ Process*|*Privilege*|*Chroot*|*labwc*|*falkon*|*Falkon*|*QtWebEngine*|*QtWeb*)
          # fields 14/15 of /proc/pid/stat are utime/stime in ticks
          set -- $(awk '{print $14, $15}' "$d/stat" 2>/dev/null)
          ut=$1 st=$2
          rss=$(awk '/^VmRSS:/{print $2}' "$d/status" 2>/dev/null)
          echo "  pid=$pid comm=$comm utime=$ut stime=$st rss_kb=${rss:-0}"
          ;;
      esac
    done
  } | tee /dev/ttyS0
  sleep 2
done
