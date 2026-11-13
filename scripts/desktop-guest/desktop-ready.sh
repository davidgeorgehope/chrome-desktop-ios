#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DISPLAY="${DISPLAY:-:0}"
export HOME=/root
export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-virtio_gpu}"
export LIBGL_ALWAYS_SOFTWARE=0
sleep 2
echo "===DESKTOP_READY=== $(date) uptime=$(cat /proc/uptime) display=$DISPLAY" | tee /dev/ttyS0
(command -v glxinfo >/dev/null && glxinfo -B) > /tmp/glxinfo.txt 2>&1 || true
echo "===GLXINFO===" | tee /dev/ttyS0
cat /tmp/glxinfo.txt | tee /dev/ttyS0
# If we still got llvmpipe, say so clearly
if grep -q llvmpipe /tmp/glxinfo.txt 2>/dev/null; then
  echo "===GL_IS_LLVMPIPE=== retry without override" | tee /dev/ttyS0
  unset MESA_LOADER_DRIVER_OVERRIDE
  glxinfo -B > /tmp/glxinfo-default.txt 2>&1 || true
  echo "===GLXINFO_DEFAULT===" | tee /dev/ttyS0
  cat /tmp/glxinfo-default.txt | tee /dev/ttyS0
fi
# fps: glxgears prints a line every 5s; run 16s for three samples
echo "===GLXGEARS_START=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
if command -v timeout >/dev/null; then
  timeout -s INT 16 glxgears -info > /tmp/glxgears.txt 2>&1 || true
else
  glxgears -info > /tmp/glxgears.txt 2>&1 &
  GPID=$!
  sleep 16
  kill -INT "$GPID" 2>/dev/null || true
  wait "$GPID" 2>/dev/null || true
fi
echo "===GLXGEARS_END=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
cat /tmp/glxgears.txt | tee /dev/ttyS0
# terminal launch
echo "===TERM_START=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
xfce4-terminal > /tmp/term.log 2>&1 &
sleep 3
echo "===TERM_AFTER_3S=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
# firefox to a light page (blank). 45s budget.
if command -v firefox >/dev/null; then
  echo "===FIREFOX_START=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
  firefox --new-instance about:blank > /tmp/firefox.log 2>&1 &
  sleep 20
  echo "===FIREFOX_AFTER_20S=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
  tail -20 /tmp/firefox.log | tee /dev/ttyS0
fi
echo "===DESKTOP_BENCH_DONE=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
