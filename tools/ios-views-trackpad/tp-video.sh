#!/bin/bash
# usage: tp-video.sh URL  (sim only) launch with autoplay, then probe <video> + audio state, screenshot TVOut and phone.
U=DE1E2D59-E674-4EE1-8096-097886FB5917
pkill -x chrome_views_ios; sleep 1
cd ~/chromium-build/logs/views-m2
WAIT=${WAIT:-30} bash run-tvout.sh --no-first-run --no-default-browser-check --hide-crash-restore-bubble --remote-debugging-port=9333 '--remote-allow-origins=*' --autoplay-policy=no-user-gesture-required "$1" >/tmp/tvout.out 2>&1
R=$(ls -td run/* | head -1); echo "$1" > $R/url.txt
grep -q "willConnect role=UIWindowSceneSessionRoleExternalDisplay" $R/stderr.txt || { xcrun simctl io $U screenConfig --display=TVOut power off >/dev/null 2>&1; sleep 2; xcrun simctl io $U screenConfig --display=TVOut power on >/dev/null 2>&1; sleep 10; echo replugged; }
for i in 1 2 3; do
  sleep ${STEP:-8}
  pgrep -x chrome_views_ios >/dev/null || { echo "DEAD at probe $i"; grep -m1 -E "FATAL|Received signal" $R/stderr.txt; break; }
  echo "probe $i: $(python3 /tmp/uaecho/eval.py '(()=>{const v=document.querySelector("video");return v?{paused:v.paused,t:Math.round(v.currentTime*10)/10,muted:v.muted,vol:v.volume,w:v.videoWidth,h:v.videoHeight,rs:v.readyState,err:v.error&&v.error.code}:null})()')"
done
xcrun simctl io $U screenshot --display=TVOut $R/video-tvout.png >/dev/null 2>&1
xcrun simctl io $U screenshot $R/video-phone.png >/dev/null 2>&1
echo $R
