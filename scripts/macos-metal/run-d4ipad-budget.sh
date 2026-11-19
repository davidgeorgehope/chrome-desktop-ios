#!/bin/bash
# Usage: run-d4ipad-budget.sh BUDGET EXEC tags...  (tags like cr-1)
D=$HOME/linux-ios-bakeoff/notes/ios-interactive
JB=$1; JE=$2; shift 2
for t in "$@"; do
  b=${t%-*}
  img=alpine-3.24.2-desktop-labwc-interactive-$b-20261113.ext4
  for try in 1 2 3 4 5 6; do
    $D/run-d4ipad-interactive.sh jit$JB-$t $img $JB $JE > $D/run-jit$JB-$t.out 2>&1; rc=$?
    [ $rc = 3 ] || break
    echo "preflight refused $t try=$try $(date)" >> $D/run-budget.status; sleep 60
  done
  echo "DONE jit$JB-$t rc=$rc $(date)" >> $D/run-budget.status
  sleep 20
done
echo ALL_DONE $JB >> $D/run-budget.status
