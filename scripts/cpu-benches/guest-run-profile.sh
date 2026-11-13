#!/bin/sh
# Profile-focused guest entry: run selected CPU benches, then power off so
# the host process can dump UML_JIT_PROFILE counters.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export TERM=linux
export SH_FOR_LOOP=/bin/sh
export OPENSSL_BIN=openssl
export CC=cc
PACK=/usr/local/share/cpu-benches

if [ -f "$PACK/profile.env" ]; then
  # shellcheck disable=SC1090
  . "$PACK/profile.env"
fi

if [ ! -s /etc/resolv.conf ] || ! grep -q nameserver /etc/resolv.conf 2>/dev/null; then
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 10.0.2.3\n' > /etc/resolv.conf
fi
if ! ip route show default 2>/dev/null | grep -q default; then
  ip link set eth0 up 2>/dev/null || true
  udhcpc -i eth0 -n -q -t 5 -T 1 2>/dev/null || true
fi

if [ -x "$PACK/run-cpu-benches.sh" ]; then
  "$PACK/run-cpu-benches.sh" 2>&1 | tee /tmp/benches.log | tee /dev/ttyS0
else
  echo "CPU pack missing" | tee /dev/ttyS0
fi
echo "===GUEST_PROFILE_DONE===" | tee /dev/ttyS0
exec /sbin/poweroff -f
