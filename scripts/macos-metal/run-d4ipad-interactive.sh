#!/bin/bash
# Usage: run-d4ipad-interactive.sh TAG ROOTFS
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
TAG=$1; ROOTFS=$2; JB=${3:-3584M}; JE=${4:-64M}; GM=${5:-3072}
D=$HOME/linux-ios-bakeoff/notes/ios-interactive
N=$HOME/linux-ios-bakeoff/notes/macos-metal-desktop
C=$HOME/Library/Containers/APP-CONTAINER-UUID/Data/Documents
if pgrep -f '[u]ml-darwin|[x]codebuild' >/dev/null; then echo "refuse: overlap"; pgrep -lf '[u]ml-darwin|[x]codebuild'; exit 2; fi
START=$(date +%s); echo "RUN_START $(date) tag=$TAG"
$N/bootstrap-d4ipad-0022.sh "$TAG" "$ROOTFS" "$JB" "$JE" "$GM"
for i in $(seq 1 1200); do [ -f $N/d4ipad-0022-last-exit.txt ] && break; if grep -q refusing $HOME/Library/Logs/d4ipad-0022-launch.stderr.log 2>/dev/null; then echo PREFLIGHT_REFUSED; cat $HOME/Library/Logs/d4ipad-0022-launch.stderr.log; launchctl bootout gui/501/com.davidhope.d4ipad-0022 2>/dev/null; exit 3; fi; sleep 1; done
echo "RUN_END $(date) exit=$(cat $N/d4ipad-0022-last-exit.txt 2>/dev/null) secs=$(( $(date +%s)-START ))"
launchctl bootout gui/501/com.davidhope.d4ipad-0022 2>/dev/null || true
OUT=$D/d4ipad-$TAG-serial-$(date +%Y%m%d-%H%M%S).log
cp $C/guest-serial.log $OUT; cp $C/guest-session.log ${OUT%-serial-*}-guestsession-${OUT##*-serial-}
echo "SERIAL=$OUT"
tr -d '\r' < $OUT | grep -a -E 'INTERACTIVE_(LAUNCH|SCROLL|INPUT|WARM|DONE|CLICK|KEY|ERROR|TIMEOUT)|DESKTOP_READY|BENCH_DONE|CHROMIUM_MISSING' | cut -c1-300 | head -30
grep -a -E 'SWAP_ABORT' $N/kernarium-ipad-0022-$TAG-memory-*.log 2>/dev/null | tail -2
