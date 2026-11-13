#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DISPLAY="${DISPLAY:-:0}"
export HOME=/root
export LIBGL_ALWAYS_SOFTWARE=0
unset MESA_LOADER_DRIVER_OVERRIDE
# Prefer virtio/virgl; if it fails, zink (Venus) then llvmpipe.
export MESA_GL_VERSION_OVERRIDE=
export MOZ_ENABLE_WAYLAND=0
export MOZ_WEBRENDER=0
export MOZ_ACCELERATED=1
echo "===DESKTOP_READY=== $(date) uptime=$(cat /proc/uptime) display=$DISPLAY" | tee /dev/ttyS0
LIBGL_DEBUG=verbose glxinfo -B > /tmp/glxinfo.txt 2>&1 || true
echo "===GLXINFO===" | tee /dev/ttyS0
# keep this short
grep -E 'OpenGL renderer|OpenGL vendor|OpenGL core profile version|Device:|libGL:|virtio|virgl|llvmpipe|zink|venus' /tmp/glxinfo.txt | tee /dev/ttyS0
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
grep -E 'GL_RENDERER|frames in|OpenGL' /tmp/glxgears.txt | tee /dev/ttyS0
# vkcube if present
if command -v vkcube >/dev/null; then
  echo "===VKCUBE_START=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
  timeout -s INT 12 vkcube --c 300 > /tmp/vkcube.txt 2>&1 || true
  echo "===VKCUBE_END=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
  cat /tmp/vkcube.txt | tee /dev/ttyS0
fi
echo "===TERM_START=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
xfce4-terminal > /tmp/term.log 2>&1 &
sleep 3
echo "===TERM_AFTER_3S=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
# Browser: Firefox first, Falkon if it doesn't paint
launch_browser() {
  if command -v firefox >/dev/null; then
    echo "===FIREFOX_START=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
    firefox --new-instance --display="$DISPLAY" "https://example.com" > /tmp/firefox.log 2>&1 &
    # poll for a mapped window up to 45s
    i=0
    while [ "$i" -lt 45 ]; do
      if xdotool search --class firefox >/dev/null 2>&1 || \
         xwininfo -root -tree 2>/dev/null | grep -qi firefox; then
        echo "===FIREFOX_WINDOW=== $(date) uptime=$(cat /proc/uptime) after=${i}s" | tee /dev/ttyS0
        return 0
      fi
      i=$((i + 1))
      sleep 1
    done
    echo "===FIREFOX_NO_WINDOW=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
    tail -30 /tmp/firefox.log | tee /dev/ttyS0
  fi
  if command -v falkon >/dev/null; then
    echo "===FALKON_START=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
    falkon "https://example.com" > /tmp/falkon.log 2>&1 &
    i=0
    while [ "$i" -lt 30 ]; do
      if xwininfo -root -tree 2>/dev/null | grep -qi falkon; then
        echo "===FALKON_WINDOW=== $(date) uptime=$(cat /proc/uptime) after=${i}s" | tee /dev/ttyS0
        return 0
      fi
      i=$((i + 1))
      sleep 1
    done
    echo "===FALKON_NO_WINDOW=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
  fi
  return 1
}
launch_browser
echo "===DESKTOP_BENCH_DONE=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
