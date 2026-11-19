#!/bin/bash
# crate-measure.sh TAG BROWSER : one boot -> desktop -> browser metrics run (same page and markers as
# Kernarium's measure-interactive.sh); VNC key+click once the page arms. After the warm page, re-open
# the metrics page in the running browser once for a supplemental warm scroll pass.
D=$HOME/linux-ios-bakeoff/scratch/crate-bench; L=$D/logs/$1.log; B=$2
( for i in $(seq 1 600); do
    if grep -aq "INTERACTIVE_READY_FOR_INPUT" $L 2>/dev/null; then sleep 0.5
      python3 $D/crate/tools/vnc.py $D/vnc.sock key a; sleep 0.3; python3 $D/crate/tools/vnc.py $D/vnc.sock click 960 400
      echo "[poke] VNC key+click $(date)" >> $D/logs/$1.poke; break; fi
    sleep 0.5; done
  for i in $(seq 1 600); do grep -aq "INTERACTIVE_WARM_LAUNCH" $L 2>/dev/null && break; sleep 0.5; done
  if [ "$B" = chromium ]; then o='chromium --user-data-dir=$HOME/.config/chromium-bench'; else o='firefox-esr --profile $HOME/.mozilla/firefox/bench'; fi
  $D/gssh "DISPLAY=:0 nohup $o 'http://127.0.0.1:8765/?pass=2' >/dev/null 2>&1 &
    for i in \$(seq 1 120); do [ \$(grep -c INTERACTIVE_SCROLL= /tmp/interactive-metrics.log) -ge 2 ] && break; sleep 0.5; done
    echo \"===WARMSCROLL_DONE=== \$(grep INTERACTIVE_SCROLL= /tmp/interactive-metrics.log | tail -1)\" > /dev/ttyAMA0" ) &
PK=$!
$D/crate-launch.sh "$1" 300 "WARMSCROLL_DONE"
kill $PK 2>/dev/null
grep -aE "===(DESKTOP_READY|FIREFOX_START|CHROMIUM_START|INTERACTIVE_LAUNCH|INTERACTIVE_SCROLL|INTERACTIVE_INPUT|INTERACTIVE_WARM_LAUNCH|WARMSCROLL_DONE)===" $L | cut -c1-200
