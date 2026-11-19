#!/bin/bash
# Trackpad test on a loaded page: scroll, web click+type into YouTube search, right-click.
U=DE1E2D59-E674-4EE1-8096-097886FB5917
R=$(ls -td ~/chromium-build/logs/views-m2/run/* | head -1)
E(){ python3 /tmp/uaecho/eval.py "$1"; }
sw(){ axe swipe --start-x $1 --start-y $2 --end-x $3 --end-y $4 --duration 0.5 --udid $U >/dev/null 2>&1; sleep 0.5; }
shot(){ xcrun simctl io $U screenshot --display=TVOut $R/$1.png >/dev/null 2>&1; }
cur(){ grep -oE "trackpad cursor=.*" $R/stderr.txt | tail -1; }
echo "scrollY0=$(E 'scrollY') url=$(E 'location.href')"
# cursor to page centre: pin (0,0) then +400,+225 pt (~960,540 px)
sw 420 360 20 40; sw 420 360 20 40; sw 30 100 430 325; cur
shot yt-0
axe gesture two-finger-swipe -x 200 -y 330 --x2 260 --y2 330 --end-x 200 --end-y 130 --end-x2 260 --end-y2 130 --udid $U >/dev/null 2>&1; sleep 2
echo "scrollY1=$(E 'scrollY')"; shot yt-scrolled
axe gesture two-finger-swipe -x 200 -y 130 --x2 260 --y2 130 --end-x 200 --end-y 330 --end-x2 260 --end-y2 330 --udid $U >/dev/null 2>&1; sleep 2
echo "scrollY2=$(E 'scrollY')"
# YouTube search box rect (CSS px == TVOut px, contents origin at y=92)
RECT=$(E '(()=>{const e=document.querySelector("input[name=search_query]")||document.querySelector("input#search");if(!e)return null;const r=e.getBoundingClientRect();return [Math.round(r.x+r.width/2),Math.round(r.y+r.height/2)]})()')
echo "search rect=$RECT"
