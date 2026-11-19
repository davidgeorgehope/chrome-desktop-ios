#!/bin/bash
# Usage: notify-poke.sh <job> <status> <rc> <detail-file>
# Optional: POSTs a JSON job-status message to a webhook (POKE_URL, POKE_KEY
# from the environment or ~/.config/mini-usb-pipeline-webhook.env). Never echoes secrets.
set -u
JOB=$1; ST=$2; RC=$3; DF=${4:-/dev/null}
ENVF="$HOME/.config/mini-usb-pipeline-webhook.env"
[ -f "$ENVF" ] && { set -a; . "$ENVF"; set +a; }
[ -n "${POKE_URL:-}" ] && [ -n "${POKE_KEY:-}" ] || { echo "notify: no webhook env"; exit 1; }
PAYLOAD=$(/usr/bin/python3 -c "
import json,sys
d=open(sys.argv[4],errors=\"replace\").read()[-1500:]
print(json.dumps({\"event\":\"job\",\"job\":sys.argv[1],\"status\":sys.argv[2],\"rc\":int(sys.argv[3]),\"detail\":\"%s status=%s rc=%s\n%s\"%(sys.argv[1],sys.argv[2],sys.argv[3],d)}))
" "$JOB" "$ST" "$RC" "$DF")
code=$(curl -s -m 20 -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $POKE_KEY" -d "$PAYLOAD" "$POKE_URL")
echo "$(date "+%F %T %Z") notify $JOB $ST http=$code" >> "$HOME/chromium-build/logs/notify.log"
