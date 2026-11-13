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
chmod +x "$ROOT/metrics-httpd" /usr/local/bin/metrics-httpd 2>/dev/null || true
METRICS_HTTPD=""
if [ -x "$ROOT/metrics-httpd" ]; then
  METRICS_HTTPD="$ROOT/metrics-httpd"
elif [ -x /usr/local/bin/metrics-httpd ]; then
  METRICS_HTTPD=/usr/local/bin/metrics-httpd
fi
if [ -n "$METRICS_HTTPD" ]; then
  "$METRICS_HTTPD" "$ROOT" > /tmp/interactive-httpd.log 2>&1 &
else
  if ! command -v httpd >/dev/null 2>&1 && ! command -v busybox >/dev/null 2>&1; then
    echo "===INTERACTIVE_MISSING=== no metrics-httpd or busybox httpd" | tee /dev/ttyS0
    exit 0
  fi
  httpd_bin=httpd
  command -v httpd >/dev/null 2>&1 || httpd_bin="busybox httpd"
  # busybox httpd: -p port, -h home. Alpine's busybox often has no httpd applet.
  # shellcheck disable=SC2086
  $httpd_bin -p "$PORT" -h "$ROOT" > /tmp/interactive-httpd.log 2>&1 &
fi
echo $! > /tmp/interactive-httpd.pid
# wait briefly for the port
i=0
up=0
while [ "$i" -lt 40 ]; do
  if wget -q -O /dev/null "http://127.0.0.1:${PORT}/cgi-bin/report" 2>/dev/null      || wget -q -O /dev/null "http://127.0.0.1:${PORT}/" 2>/dev/null; then
    up=1
    break
  fi
  i=$((i + 1))
  sleep 0.1
done
if [ "$up" -ne 1 ]; then
  echo "===INTERACTIVE_HTTPD_FAIL=== port=$PORT" | tee /dev/ttyS0
  cat /tmp/interactive-httpd.log 2>/dev/null | tee /dev/ttyS0
  exit 0
fi

# After the page arms, inject a real key and a click via the UML VNC
# evdev nodes so input latency is measurable without a host VNC client.
(
  i=0
  while [ "$i" -lt 250 ]; do
    if grep -q "INTERACTIVE_READY_FOR_INPUT" /tmp/interactive-metrics.log 2>/dev/null; then
      sleep 0.5
      poke=""
      for c in \
        /usr/local/share/interactive-metrics/evdev-poke.sh \
        /usr/local/bin/evdev-poke.sh
      do
        [ -x "$c" ] && poke=$c && break
      done
      if [ -n "$poke" ]; then
        chmod +x "$poke" 2>/dev/null || true
        sh "$poke"
      else
        echo "===INTERACTIVE_EVDEV_POKE=== why=no_helper" | tee /dev/ttyS0
      fi
      exit 0
    fi
    i=$((i + 1))
    sleep 0.2
  done
) >/tmp/interactive-evdev-poke.log 2>&1 &
echo $! > /tmp/interactive-evdev-poke.pid

echo "===INTERACTIVE_HTTPD=== port=$PORT root=$ROOT pid=$(cat /tmp/interactive-httpd.pid 2>/dev/null)" | tee /dev/ttyS0
