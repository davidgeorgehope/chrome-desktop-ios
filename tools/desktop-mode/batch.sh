#!/bin/bash
OUT=/tmp/uaecho/sites; mkdir -p $OUT; : > $OUT/results.jsonl
while read -r tag wait url; do
  pkill -x chrome_views_ios; sleep 2
  r=$(WAIT=$wait /tmp/site.sh "$url" | head -1)
  R=~/chromium-build/logs/views-m2/$(echo $r | awk '{print $2}')
  cp $R/tvout.png $OUT/$tag-tvout.png 2>/dev/null
  j=$(python3 /tmp/uaecho/cdp.py 2>&1 | tail -1)
  echo "{\"tag\":\"$tag\",\"url\":\"$url\",\"state\":\"$(echo $r|awk '{print $1}')\",\"t\":\"$(date +%H:%M:%S)\",\"probe\":$(python3 -c 'import json,sys;s=sys.argv[1];
try: json.loads(s); print(s)
except Exception: print(json.dumps(s))' "$j")}" >> $OUT/results.jsonl
done <<'EOF'
whatismybrowser 45 https://www.whatismybrowser.com/
youtube 60 https://www.youtube.com/
wikipedia 40 https://en.wikipedia.org/wiki/Main_Page
reddit 50 https://www.reddit.com/
x 50 https://x.com/
google 30 https://www.google.com/search?q=chromium
EOF
echo BATCH_DONE
