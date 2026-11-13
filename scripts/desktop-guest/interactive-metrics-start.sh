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
evdev_poke() {
  evdev_le16() { printf "\\$(printf '%03o' $(($1 & 255)))\\$(printf '%03o' $((($1 >> 8) & 255)))"; }
  evdev_le32() {
    printf "\\$(printf '%03o' $(($1 & 255)))\\$(printf '%03o' $((($1 >> 8) & 255)))"
    printf "\\$(printf '%03o' $((($1 >> 16) & 255)))\\$(printf '%03o' $((($1 >> 24) & 255)))"
  }
  evdev_event() {
    # 16-byte timeval + type u16 + code u16 + value i32 (aarch64/x86_64)
    printf '\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0'
    evdev_le16 "$1"
    evdev_le16 "$2"
    evdev_le32 "$3"
  }
  kbd=""
  tablet=""
  if [ -f /proc/bus/input/devices ]; then
    kbd=$(awk '
      BEGIN { FS="\n"; RS=""; }
      /VNC Keyboard|Name=".*[Kk]eyboard/ { for (i=1;i<=NF;i++) if ($i ~ /event[0-9]+/) {
        if (match($i, /event[0-9]+/)) { print "/dev/input/" substr($i, RSTART, RLENGTH); exit }
      }}
    ' /proc/bus/input/devices)
    tablet=$(awk '
      BEGIN { FS="\n"; RS=""; }
      /VNC Tablet|Name=".*[Tt]ablet/ { for (i=1;i<=NF;i++) if ($i ~ /event[0-9]+/) {
        if (match($i, /event[0-9]+/)) { print "/dev/input/" substr($i, RSTART, RLENGTH); exit }
      }}
    ' /proc/bus/input/devices)
  fi
  [ -z "$kbd" ] && [ -e /dev/input/event0 ] && kbd=/dev/input/event0
  [ -z "$tablet" ] && [ -e /dev/input/event1 ] && tablet=/dev/input/event1
  echo "===INTERACTIVE_EVDEV_POKE=== kbd=$kbd tablet=$tablet" | tee /dev/ttyS0
  if [ -n "$kbd" ] && [ -w "$kbd" ]; then
    # KEY_A=30 down, syn, up, syn
    { evdev_event 1 30 1; evdev_event 0 0 0; evdev_event 1 30 0; evdev_event 0 0 0; } >"$kbd"
    sleep 0.3
    { evdev_event 1 30 1; evdev_event 0 0 0; evdev_event 1 30 0; evdev_event 0 0 0; } >"$kbd"
  fi
  if [ -n "$tablet" ] && [ -w "$tablet" ]; then
    # ABS_X/ABS_Y mid-window-ish, BTN_LEFT=272 down/up (units depend on the
    # tablet abs range; 960,400 is a reasonable 1920x1080 guess, also try
    # abs max midpoints if 0..65535).
    { evdev_event 3 0 960; evdev_event 3 1 400; evdev_event 0 0 0
      evdev_event 1 272 1; evdev_event 0 0 0
      evdev_event 1 272 0; evdev_event 0 0 0
    } >"$tablet" || true
  fi
}

(
  i=0
  while [ "$i" -lt 250 ]; do
    if grep -q "INTERACTIVE_READY_FOR_INPUT" /tmp/interactive-metrics.log 2>/dev/null; then
      sleep 0.5
      evdev_poke
      exit 0
    fi
    i=$((i + 1))
    sleep 0.2
  done
) >/tmp/interactive-evdev-poke.log 2>&1 &
echo $! > /tmp/interactive-evdev-poke.pid

echo "===INTERACTIVE_HTTPD=== port=$PORT root=$ROOT pid=$(cat /tmp/interactive-httpd.pid 2>/dev/null)" | tee /dev/ttyS0
