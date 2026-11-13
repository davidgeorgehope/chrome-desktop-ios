#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
echo "===INSTALL_FAST_DESKTOP=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
ls -l /usr/local/bin/start-desktop.sh /usr/local/bin/bwrap-passthrough.sh 2>/dev/null | tee /dev/ttyS0
# Confirm the new script is the one we just baked (marker in the header).
if grep -q 'gly-hdl-loader' /usr/local/bin/start-desktop.sh 2>/dev/null; then
  echo "INSTALL_MARKER_OK" | tee /dev/ttyS0
else
  echo "INSTALL_MARKER_MISSING" | tee /dev/ttyS0
fi
sync
echo "===INSTALL_FAST_DESKTOP_DONE===" | tee /dev/ttyS0
exec poweroff -f
