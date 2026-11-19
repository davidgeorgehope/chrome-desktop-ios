#!/bin/bash
# YouTube via phone trackpad (sim only): click search box, type $1, Return, click first video.
U=${SIM_UDID:-booted}
R=$(ls -td ~/chromium-build/logs/views-m2/run/* | head -1)
E(){ python3 /tmp/uaecho/eval.py "$1"; }
shot(){ xcrun simctl io $U screenshot --display=TVOut $R/$1.png >/dev/null 2>&1; }
OX=4; OY=$(E 'window.screenY===undefined?92:92')   # contents origin on TVOut
pos(){ E "(()=>{const e=document.querySelector('$1');if(!e)return null;const r=e.getBoundingClientRect();return (Math.round(r.x+r.width/2)+$OX)+' '+(Math.round(r.y+r.height/2)+92)})()" | tr -d '"'; }
P=$(pos 'input[name=search_query]'); echo "search at $P"
python3 /tmp/tp-goto.py $P 2>/dev/null
axe tap -x 233 -y 200 --udid $U >/dev/null 2>&1; sleep 1
echo "active=$(E 'document.activeElement&&document.activeElement.name')"
axe type "$1" --udid $U >/dev/null 2>&1; sleep 1; shot yt-typed
echo "value=$(E 'document.querySelector("input[name=search_query]").value')"
axe key 40 --udid $U >/dev/null 2>&1; sleep 10; shot yt-results
echo "url=$(E 'location.href')"
P=$(pos 'ytd-video-renderer a#thumbnail'); echo "first video at $P"
[ "$P" != "null" ] && python3 /tmp/tp-goto.py $P 2>/dev/null && axe tap -x 233 -y 200 --udid $U >/dev/null 2>&1
sleep 15; shot yt-watch
echo "url=$(E 'location.href')"
echo "video=$(E '(()=>{const v=document.querySelector("video");return v?{paused:v.paused,t:Math.round(v.currentTime*10)/10,w:v.videoWidth,h:v.videoHeight,rs:v.readyState}:null})()')"
