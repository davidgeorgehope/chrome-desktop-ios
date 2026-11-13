#!/bin/sh
# Replaces /usr/local/bin/run-benches.sh in the slim Alpine image.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export TERM=linux
export SH_FOR_LOOP=/bin/sh
export OPENSSL_BIN=openssl
export CC=cc
PACK=/usr/local/share/cpu-benches

# The slim image often has an empty resolv.conf even when slirp NAT is up.
if [ ! -s /etc/resolv.conf ] || ! grep -q nameserver /etc/resolv.conf 2>/dev/null; then
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 10.0.2.3\n' > /etc/resolv.conf
fi
# Best-effort DHCP if there is no default route yet.
if ! ip route show default 2>/dev/null | grep -q default; then
  ip link set eth0 up 2>/dev/null || true
  udhcpc -i eth0 -n -q -t 5 -T 1 2>/dev/null || true
fi

if [ -x "$PACK/run-cpu-benches.sh" ]; then
  "$PACK/run-cpu-benches.sh" 2>&1 | tee /tmp/benches.log | tee /dev/ttyS0
else
  echo "CPU pack missing" | tee /dev/ttyS0
fi
echo "===GUEST_BENCH_SLEEP===" | tee /dev/ttyS0
sleep 30
exec /sbin/getty -n -l /sbin/autologin-root 115200 ttyS0 vt100
