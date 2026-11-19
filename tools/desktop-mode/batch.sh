#!/bin/bash
OUT=/tmp/uaecho/sites; mkdir -p $OUT; : > $OUT/results.jsonl; : > $OUT/runs.txt
while read -r tag wait url; do
  pkill -x chrome_views_ios; sleep 2
  # site.sh may print "(TVOut re-plugged)" first; take the ALIVE/DEAD line.
  r=$(WAIT=$wait /tmp/site.sh "$url" | grep -E '^(ALIVE|DEAD) ' | head -1)
  R=$(echo $r | awk '{print $2}'); case $R in /*) ;; *) R=~/chromium-build/logs/views-m2/$R;; esac
  j=$(python3 /tmp/uaecho/cdp.py 2>&1 | tail -1)
  # Fresh screenshot of this run, after the probe (never a stale file).
  rm -f $OUT/$tag-tvout.png
  xcrun simctl io ${SIM_UDID:-booted} screenshot --display=TVOut $OUT/$tag-tvout.png >/dev/null 2>&1
  echo "$tag $R $(date +%T)" >> $OUT/runs.txt
  echo "{\"tag\":\"$tag\",\"url\":\"$url\",\"state\":\"$(echo $r|awk '{print $1}')\",\"t\":\"$(date +%H:%M:%S)\",\"probe\":$(python3 -c 'import json,sys;s=sys.argv[1];
try: json.loads(s); print(s)
except Exception: print(json.dumps(s))' "$j")}" >> $OUT/results.jsonl
done <<'EOF'
echo 30 http://127.0.0.1:8765/
echovp400 30 http://127.0.0.1:8765/echo?vp=400
whatismybrowser 45 https://www.whatismybrowser.com/
youtube 60 https://www.youtube.com/
wikipedia 40 https://en.wikipedia.org/wiki/Main_Page
reddit 50 https://www.reddit.com/
x 50 https://x.com/
google 30 https://www.google.com/search?q=chromium
EOF
echo BATCH_DONE
