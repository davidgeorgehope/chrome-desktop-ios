#!/bin/sh
# /usr/local/bin/run-benches.sh for the slim Alpine image: gcc from the offline apks,
# python3 + nodejs from the network, then cmp-benches.sh, then power off.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root TERM=linux
P=/usr/local/share/cpu-benches
if [ ! -s /etc/resolv.conf ] || ! grep -q nameserver /etc/resolv.conf 2>/dev/null; then
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 10.0.2.3\n' > /etc/resolv.conf; fi
if ! ip route show default 2>/dev/null | grep -q default; then
  ip link set eth0 up 2>/dev/null || true; udhcpc -i eth0 -n -q -t 5 -T 1 2>/dev/null || true; fi
mkdir -p /tmp/apks && tar -C /tmp/apks -xf $P/apks.tar
apk add --allow-untrusted --force-non-repository --no-network /tmp/apks/*.apk >/dev/null 2>&1
apk add --no-cache python3 nodejs > /tmp/apk-net.log 2>&1; echo "===CMPB_APK=== rc=$? $(tail -1 /tmp/apk-net.log)" > /dev/ttyS0
sh $P/cmp-benches.sh /dev/ttyS0
sh $P/cmp-benches.sh /dev/ttyS0
sync; poweroff -f
