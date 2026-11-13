#!/bin/sh
# Start a loopback httpd that serves the interactive-metrics page and
# writes browser-posted markers to the UML serial. Idempotent.
set -eu
ROOT=/usr/local/share/interactive-metrics
LOG=/tmp/interactive-metrics.log
PORT=8765
if [ ! -d "$ROOT" ]; then
  echo "===INTERACTIVE_MISSING=== no $ROOT" | tee /dev/ttyS0
  exit 0
fi
chmod 755 "$ROOT/cgi-bin/report" 2>/dev/null || true
: > "$LOG"
# Already up?
if wget -q -O /dev/null "http://127.0.0.1:${PORT}/cgi-bin/report" 2>/dev/null; then
  echo "===INTERACTIVE_HTTPD=== already port=$PORT" | tee /dev/ttyS0
  exit 0
fi
if ! command -v httpd >/dev/null 2>&1 && ! command -v busybox >/dev/null 2>&1; then
  echo "===INTERACTIVE_MISSING=== no busybox httpd" | tee /dev/ttyS0
  exit 0
fi
httpd_bin=httpd
command -v httpd >/dev/null 2>&1 || httpd_bin="busybox httpd"
# busybox httpd: -p port, -h home, -f stay in foreground
# shellcheck disable=SC2086
$httpd_bin -p "127.0.0.1:$PORT" -h "$ROOT" > /tmp/interactive-httpd.log 2>&1 &
echo $! > /tmp/interactive-httpd.pid
# wait briefly for the port
i=0
while [ "$i" -lt 20 ]; do
  if wget -q -O /dev/null "http://127.0.0.1:${PORT}/cgi-bin/report" 2>/dev/null; then
    break
  fi
  i=$((i + 1))
  sleep 0.1
done
echo "===INTERACTIVE_HTTPD=== port=$PORT root=$ROOT pid=$(cat /tmp/interactive-httpd.pid 2>/dev/null)" | tee /dev/ttyS0
