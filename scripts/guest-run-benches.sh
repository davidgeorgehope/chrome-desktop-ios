#!/bin/sh
# Auto-run bakeoff benches on first boot after OpenRC default.
# Prints to ttyS0 (simctl console-pty), tty0 (framebuffer), and /tmp/benches.log.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export TERM=linux

# Wait for DHCP so apk can reach Alpine mirrors.
i=0
while [ "$i" -lt 40 ]; do
  if ip route | grep -q default; then
    break
  fi
  i=$((i + 1))
  sleep 1
done

run() {
  echo
  echo "======== $1 ========"
  shift
  "$@"
}

{
  echo "===BENCH_START==="
  date
  echo "uptime: $(cat /proc/uptime)"
  run uname uname -a
  run os_release sed -n '1,5p' /etc/os-release
  run sh_loop time sh -c 'i=0; while [ $i -lt 20000 ]; do i=$((i+1)); done'
  run dd_null dd if=/dev/zero of=/dev/null bs=1M count=32
  run dd_write32 dd if=/dev/zero of=/tmp/32m bs=1M count=32
  run sha256_32m time sha256sum /tmp/32m
  run apk_add_tree time apk add --no-cache tree
  echo "APK_TREE_EXIT:$?"
  tree --version 2>/dev/null | head -1
  run apk_add_openssl time apk add --no-cache openssl
  echo "APK_OPENSSL_EXIT:$?"
  openssl version 2>/dev/null
  run openssl_speed openssl speed -seconds 3 -evp sha256 aes-256-cbc
  echo "===BENCH_DONE==="
  date
  echo "uptime: $(cat /proc/uptime)"
} 2>&1 | tee /tmp/benches.log | tee /dev/ttyS0 > /dev/tty0

# Leave a compact summary at the bottom of the framebuffer.
{
  echo
  echo "===== BENCH SUMMARY ====="
  grep -E '^(real |user |sys |===|APK_|[0-9]+ |The .+ is |sha256|Linux |PRETTY|open |written |========)' /tmp/benches.log | tail -n 40
  echo "===== END SUMMARY ====="
} > /dev/tty0 2>/dev/null

# Keep the summary on the framebuffer long enough to screenshot.
sleep 25

# Interactive shells for follow-up / screenshots.
/sbin/getty -n -l /sbin/autologin-root 38400 tty0 linux &
exec /sbin/getty -n -l /sbin/autologin-root 115200 ttyS0 vt100
