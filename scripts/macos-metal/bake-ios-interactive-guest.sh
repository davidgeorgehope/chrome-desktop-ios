#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
say() { echo "$*" | tee /dev/ttyS0; }
say "===BAKE_BEGIN=== $(date) uptime=$(cat /proc/uptime)"
mount -o remount,rw / || { say "===BAKE_FAIL=== remount"; exec poweroff; }
G=""
for p in /usr/local/bin/good-start-desktop.sh /payload/usr/local/bin/good-start-desktop.sh; do [ -s "$p" ] && G=$p && break; done
[ -n "$G" ] || { say "===BAKE_FAIL=== no good start"; exec poweroff; }
cp "$G" /tmp/g.sh
cp /tmp/g.sh /usr/local/bin/start-desktop-labwc.sh
cp /tmp/g.sh /usr/local/bin/start-desktop.sh
rm -f /usr/local/bin/good-start-desktop.sh
# Make sure every payload file is on disk (copy from /payload if it exists).
if [ -d /payload/usr/local ]; then cp -a /payload/usr/local/. /usr/local/; fi
rm -f /usr/local/bin/good-start-desktop.sh
cp /tmp/g.sh /usr/local/bin/start-desktop.sh
chmod 755 /usr/local/bin/*.sh /usr/local/share/interactive-metrics/*.sh /usr/local/share/interactive-metrics/metrics-httpd /usr/local/share/interactive-metrics/cgi-bin/report 2>/dev/null
sync
say "===BAKE_LS==="
ls -l /usr/local/bin /usr/local/etc /usr/local/share/interactive-metrics /usr/local/share/interactive-metrics/cgi-bin 2>&1 | tee /dev/ttyS0
say "browser=$(cat /usr/local/etc/desktop-browser) flags=$(tr '\n' ' ' < /usr/local/etc/chromium-flags) start_bytes=$(wc -c < /usr/local/bin/start-desktop.sh) interactive=$(ls /usr/local/etc/interactive-metrics 2>&1)"
mount -o remount,ro / 2>/dev/null
say "===BAKE_DONE=== $(date)"
exec poweroff
