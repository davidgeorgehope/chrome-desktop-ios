#!/bin/bash
# Context-menu interaction on the simulator: open, Escape, reopen, outside click, reopen.
U=${SIM_UDID:-booted}
R=$(ls -td ~/chromium-build/logs/views-m2/run/* | head -1)
sw(){ axe swipe --start-x $1 --start-y $2 --end-x $3 --end-y $4 --duration 0.5 --udid $U >/dev/null 2>&1; sleep 0.6; }
shot(){ xcrun simctl io $U screenshot --display=TVOut $R/$1.png >/dev/null 2>&1; }
rtap(){ axe gesture two-finger-tap -x 200 -y 330 --x2 260 --y2 330 --udid $U >/dev/null 2>&1; sleep 1.5; }
tap(){ axe tap -x 233 -y 330 --udid $U >/dev/null 2>&1; sleep 1.5; }
cur(){ grep -oE "trackpad cursor=.*" $R/stderr.txt | tail -1; }
case "$1" in
 center) sw 420 360 20 40; sw 420 360 20 40; sw 30 100 430 325; cur;;
 open) rtap; shot ctx-${2:-open};;
 esc) axe key 41 --udid $U >/dev/null 2>&1; sleep 1; shot ctx-${2:-esc};;
 away) sw 233 330 133 330; cur; tap; shot ctx-${2:-away};;
 tap) tap; shot ctx-${2:-tap};;
esac
pgrep -x chrome_views_ios >/dev/null && echo ALIVE || echo DEAD
