#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DISPLAY="${DISPLAY:-:0}"
export HOME=/root
export LIBGL_ALWAYS_SOFTWARE=0
export MOZ_ENABLE_WAYLAND=0
export MOZ_WEBRENDER=0
export MOZ_ACCELERATED=1
# Default: no loader override. Prefer guest Zink when Venus/virtio-vulkan is
# present; otherwise virgl (or llvmpipe) as Mesa chooses.
unset MESA_LOADER_DRIVER_OVERRIDE
unset GALLIUM_DRIVER

dump_gl() {
  tag="$1"
  echo "===GLXINFO_${tag}===" | tee /dev/ttyS0
  LIBGL_DEBUG=verbose glxinfo -B > /tmp/glxinfo-${tag}.txt 2>&1 || true
  grep -E 'OpenGL renderer|OpenGL vendor|OpenGL core profile version|OpenGL version|Device:|libGL:|virtio|virgl|llvmpipe|zink|venus|Kosmic|Apple|Metal' \
    /tmp/glxinfo-${tag}.txt | tee /dev/ttyS0
}

dump_vk() {
  echo "===VULKANINFO===" | tee /dev/ttyS0
  if command -v vulkaninfo >/dev/null; then
    vulkaninfo --summary > /tmp/vulkaninfo.txt 2>&1 || vulkaninfo > /tmp/vulkaninfo.txt 2>&1 || true
    grep -E 'deviceName|driverName|driverInfo|vendorID|deviceID|apiVersion|deviceType|Khronos|virtio|Venus|llvmpipe|Kosmic|Apple|Mesa' \
      /tmp/vulkaninfo.txt | tee /dev/ttyS0
  else
    echo "vulkaninfo not installed" | tee /dev/ttyS0
  fi
}

run_gears() {
  tag="$1"
  echo "===GLXGEARS_START_${tag}=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
  if command -v timeout >/dev/null; then
    timeout -s INT 16 glxgears -info > /tmp/glxgears-${tag}.txt 2>&1 || true
  else
    glxgears -info > /tmp/glxgears-${tag}.txt 2>&1 &
    GPID=$!
    sleep 16
    kill -INT "$GPID" 2>/dev/null || true
    wait "$GPID" 2>/dev/null || true
  fi
  echo "===GLXGEARS_END_${tag}=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
  grep -E 'GL_RENDERER|GL_VENDOR|GL_VERSION|frames in|OpenGL' /tmp/glxgears-${tag}.txt | tee /dev/ttyS0
}

run_vkcube() {
  if ! command -v vkcube >/dev/null; then
    echo "===VKCUBE_SKIP=== vkcube not installed" | tee /dev/ttyS0
    return 0
  fi
  echo "===VKCUBE_START=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
  # vkcube can hang on the Venus/Zink present path (black window). Do not let
  # that block the terminal or Firefox probe. SIGINT is not enough; kill -9.
  vkcube --c 300 > /tmp/vkcube.txt 2>&1 &
  VKPID=$!
  i=0
  while [ "$i" -lt 8 ]; do
    if ! kill -0 "$VKPID" 2>/dev/null; then
      break
    fi
    i=$((i + 1))
    sleep 1
  done
  if kill -0 "$VKPID" 2>/dev/null; then
    echo "===VKCUBE_TIMEOUT=== killing pid $VKPID" | tee /dev/ttyS0
    kill -INT "$VKPID" 2>/dev/null || true
    sleep 1
    kill -KILL "$VKPID" 2>/dev/null || true
  fi
  wait "$VKPID" 2>/dev/null || true
  echo "===VKCUBE_END=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
  cat /tmp/vkcube.txt | tee /dev/ttyS0
}

renderer_is_zink() {
  grep -qi zink /tmp/glxinfo-zink.txt 2>/dev/null
}

echo "===DESKTOP_READY=== $(date) uptime=$(cat /proc/uptime) display=$DISPLAY" | tee /dev/ttyS0

dump_vk

# Probe guest Zink first (Venus / virtio-vulkan -> host KosmicKrisp).
export MESA_LOADER_DRIVER_OVERRIDE=zink
export GALLIUM_DRIVER=zink
# Zink on X11 often needs Kopper's DRI3/zink path; keep software off.
export LIBGL_KOPPER_DRI2="${LIBGL_KOPPER_DRI2:-1}"
dump_gl zink
if renderer_is_zink; then
  echo "===RENDERER_PATH=== guest_zink" | tee /dev/ttyS0
  run_gears zink
  run_vkcube
else
  echo "===RENDERER_PATH=== zink_unavailable, trying default/virgl" | tee /dev/ttyS0
  unset MESA_LOADER_DRIVER_OVERRIDE
  unset GALLIUM_DRIVER
  unset LIBGL_KOPPER_DRI2
  dump_gl default
  run_gears default
  run_vkcube
fi

echo "===TERM_START=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
xfce4-terminal > /tmp/term.log 2>&1 &
sleep 3
echo "===TERM_AFTER_3S=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0

launch_browser() {
  if command -v firefox >/dev/null; then
    echo "===FIREFOX_START=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
    firefox --new-instance --display="$DISPLAY" "https://example.com" > /tmp/firefox.log 2>&1 &
    i=0
    while [ "$i" -lt 45 ]; do
      if xdotool search --class firefox >/dev/null 2>&1 || \
         xwininfo -root -tree 2>/dev/null | grep -qi firefox || \
         xlsclients 2>/dev/null | grep -qi firefox || \
         xprop -root _NET_CLIENT_LIST_NAMES 2>/dev/null | grep -qi firefox; then
        echo "===FIREFOX_WINDOW=== $(date) uptime=$(cat /proc/uptime) after=${i}s" | tee /dev/ttyS0
        # Give the page a moment to paint, then scroll for the video.
        sleep 3
        if command -v xdotool >/dev/null; then
          WID=$(xdotool search --class firefox | head -1)
          if [ -n "$WID" ]; then
            xdotool windowactivate --sync "$WID" 2>/dev/null || true
            echo "===FIREFOX_SCROLL_START=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
            xdotool key --window "$WID" --repeat 8 --delay 200 Next 2>/dev/null || \
              xdotool key --repeat 8 --delay 200 Next 2>/dev/null || true
            sleep 1
            xdotool key --window "$WID" --repeat 8 --delay 200 Prior 2>/dev/null || \
              xdotool key --repeat 8 --delay 200 Prior 2>/dev/null || true
            echo "===FIREFOX_SCROLL_END=== $(date) uptime=$(cat /proc/uptime)" | tee /dev/ttyS0
          fi
        fi
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
