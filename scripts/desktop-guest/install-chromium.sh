#!/bin/sh
# Install Alpine's chromium package into the currently mounted rootfs.
# Must be booted with UML_BOOT_UPPER=none so writes hit the ext4, not tmpfs.
# Do not use poweroff -f: that skips umount and leaves a dirty journal.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
echo "===INSTALL_CHROMIUM_BEGIN=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
mount -o remount,rw / || {
  echo "===INSTALL_CHROMIUM_FAIL=== remount rw failed" | tee /dev/ttyS0
  sleep 2
  exec poweroff
}
echo "===INSTALL_CHROMIUM_REPOS===" | tee /dev/ttyS0
cat /etc/apk/repositories | tee /dev/ttyS0
echo "===INSTALL_CHROMIUM_DF_BEFORE===" | tee /dev/ttyS0
df -h / /tmp | tee /dev/ttyS0
ip link set lo up 2>/dev/null || true
ip link set eth0 up 2>/dev/null || true
if ! ip route | grep -q default; then
  udhcpc -i eth0 -n -q -t 10 -s /usr/share/udhcpc/default.script || true
fi
echo "===INSTALL_CHROMIUM_NET=== $(ip route | tr '\n' ';')" | tee /dev/ttyS0
apk update 2>&1 | tee /dev/ttyS0
apk add --no-cache chromium 2>&1 | tee /dev/ttyS0
status=$?
echo "===INSTALL_CHROMIUM_APK_STATUS=== $status" | tee /dev/ttyS0
echo "===INSTALL_CHROMIUM_BINS===" | tee /dev/ttyS0
command -v chromium | tee /dev/ttyS0
command -v chromium-browser | tee /dev/ttyS0
ls -l /usr/bin/chromium /usr/bin/chromium-browser /usr/lib/chromium/chromium \
      /usr/lib/chromium/chrome-sandbox /usr/lib/chromium/chrome_sandbox \
      /usr/lib/chromium/chromium-sandbox 2>/dev/null | tee /dev/ttyS0
(chromium --version || chromium-browser --version || true) 2>&1 | tee /dev/ttyS0
apk info -d chromium 2>&1 | tee /dev/ttyS0
echo "===INSTALL_CHROMIUM_DF_AFTER===" | tee /dev/ttyS0
df -h / | tee /dev/ttyS0
# Keep Firefox. Confirm it is still present.
command -v firefox | tee /dev/ttyS0
sync
if [ "$status" -eq 0 ] && { command -v chromium >/dev/null || command -v chromium-browser >/dev/null; }; then
  echo "===INSTALL_CHROMIUM_DONE=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
else
  echo "===INSTALL_CHROMIUM_FAIL=== apk or binary missing status=$status" | tee /dev/ttyS0
fi
mount -o remount,ro / 2>/dev/null || true
umount -a -r 2>/dev/null || true
sync
exec poweroff
