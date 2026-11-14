#!/bin/bash
# Usage: run-d4ipad-sweep.sh "BUDGET/EXEC/browser-n" ...   e.g. 3G/128M/cr-1
D=/Users/davidhope/linux-ios-bakeoff/notes/ios-interactive
for spec in "$@"; do
  JB=${spec%%/*}; rest=${spec#*/}; JE=${rest%%/*}; t=${rest#*/}; b=${t%-*}
  tag=sw$JB-$JE-$t
  img=alpine-3.24.2-desktop-labwc-interactive-$b-20261113.ext4
  for try in 1 2 3 4 5 6; do
    ( $D/footprint-sampler.sh $D/fp-$tag 420 & )
    $D/run-d4ipad-interactive.sh $tag $img $JB $JE > $D/run-$tag.out 2>&1; rc=$?
    [ $rc = 3 ] || break
    pkill -f "footprint-sampler.sh $D/fp-$tag"; echo "preflight refused $tag try=$try $(date)" >> $D/run-sweep.status; sleep 60
  done
  sleep 3; pkill -f "footprint-sampler.sh $D/fp-$tag"
  echo "DONE $tag rc=$rc $(date)" >> $D/run-sweep.status
  sleep 15
done
echo ALL_DONE >> $D/run-sweep.status
