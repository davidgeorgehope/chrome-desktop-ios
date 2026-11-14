#!/bin/bash
# XDG autostart in the Xfce session: mark desktop-ready, then (if
# /etc/bench-browser names one) start the metrics page server and the browser
# the same way Kernarium's start-desktop-labwc.sh does.
tty=/dev/ttyAMA0
echo "===DESKTOP_READY=== $(date) uptime=$(cat /proc/uptime) display=$DISPLAY xfce=1" > $tty
browser=$(cat /etc/bench-browser 2>/dev/null)
[ -n "$browser" ] || exit 0
pkill -f metrics_httpd.py; : > /tmp/interactive-metrics.log
/usr/local/bin/metrics_httpd.py > /tmp/metrics-httpd.log 2>&1 &
for i in $(seq 1 50); do python3 -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8765/cgi-bin/report')" 2>/dev/null && break; sleep 0.1; done
url=http://127.0.0.1:8765/
echo "===INTERACTIVE_ENABLED=== url=$url" > $tty
if [ "$browser" = chromium ]; then
  d=$HOME/.config/chromium-bench; rm -rf "$d"; mkdir -p "$d"
  echo "===CHROMIUM_START=== $(date) uptime=$(cat /proc/uptime) from_ready=0.00 bin=chromium" > $tty
  chromium --no-first-run --no-default-browser-check --user-data-dir="$d" \
    $(tr '\n' ' ' < /usr/local/etc/chromium-flags) "$url" > /tmp/chromium.log 2>&1 &
else
  P=$HOME/.mozilla/firefox/bench; rm -rf "$HOME/.mozilla" "$HOME/.cache/mozilla"; mkdir -p "$P"
  cp /usr/local/etc/firefox-user.js "$P/user.js"
  echo "===FIREFOX_START=== $(date) uptime=$(cat /proc/uptime) from_ready=0.00" > $tty
  MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 \
    firefox-esr --profile "$P" --new-instance "$url" > /tmp/firefox.log 2>&1 &
fi

# Maximize the browser on map, as Kernarium's labwc windowRule does.
( for i in $(seq 1 300); do
    w=$(wmctrl -lx 2>/dev/null | awk 'tolower($3) ~ /firefox|chromium/ {print $1; exit}')
    if [ -n "$w" ]; then wmctrl -i -r "$w" -b add,maximized_vert,maximized_horz; wmctrl -i -a "$w"; echo "===BROWSER_MAXIMIZED=== uptime=$(cat /proc/uptime)" > $tty; exit 0; fi
    sleep 0.1; done ) &
