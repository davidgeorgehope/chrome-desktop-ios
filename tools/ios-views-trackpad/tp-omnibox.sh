#!/bin/bash
# Drive the phone trackpad (sim only): cursor center -> omnibox, click, type $1, Return.
U=${SIM_UDID:-booted}
R=$(ls -td ~/chromium-build/logs/views-m2/run/* | head -1)
sw(){ axe swipe --start-x $1 --start-y $2 --end-x $3 --end-y $4 --duration 0.5 --udid $U >/dev/null 2>&1; sleep 0.5; }
sw 420 360 20 40; sw 420 360 20 40; sw 100 100 240 135
grep -oE "trackpad cursor=.*" $R/stderr.txt | tail -1
axe tap -x 233 -y 200 --udid $U >/dev/null 2>&1; sleep 1
# (keyboard: trackpad is first responder with hardware keys)
axe type "$1" --udid $U >/dev/null 2>&1; sleep 1
xcrun simctl io $U screenshot --display=TVOut $R/typed.png >/dev/null 2>&1
axe key 40 --udid $U >/dev/null 2>&1; sleep ${WAITNAV:-8}
xcrun simctl io $U screenshot --display=TVOut $R/navigated.png >/dev/null 2>&1
grep -oE "\[DeskBrowser\] trackpad (click|insertText|becomeFirst|key).{0,80}" $R/stderr.txt | tail -8
echo $R
