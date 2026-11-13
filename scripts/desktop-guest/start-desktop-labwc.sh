#!/bin/sh
# Fast labwc (Wayland) session for UML/Darwin.
#
# XFCE's remaining ~5.9 s after X is up is xfwm4/GTK/Mesa JIT (timeline
# 13 Nov 2026: cpu-bound, drm_version + gly-global-exec + Mesa disk$0).
# labwc reaches a usable compositor in ~1.3 s after dri is ready, for a
# DESKTOP_READY of ~2.4–2.6 s on the official 4K uml-darwin GPU/Zink host.
# Firefox is started immediately with a pre-created profile that skips the
# first-run/telemetry pages. A VNC capture showed the window by ~3–6 s
# after READY and the page painted by ~12 s after READY. That ~12 s is
# engine time (libxul JIT in the parent, then a content process), not
# DNS/network: a local file:// page paints on the same clock, and wget
# of example.com is 0.63 s.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export USER=root
export XDG_RUNTIME_DIR=/tmp/runtime-root
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=labwc:wlroots
export LANG=C.UTF-8
export NO_AT_BRIDGE=1
export GTK_A11Y=none
unset MESA_LOADER_DRIVER_OVERRIDE
export LIBGL_ALWAYS_SOFTWARE=0

up() { awk '{print $1}' /proc/uptime; }
ts() { echo "===TS=== $(up) $*" | tee /dev/ttyS0; }

ts script_begin
mkdir -p "$XDG_RUNTIME_DIR" /run/dbus /var/run /tmp /var/log /dev/pts /dev/shm
chmod 700 "$XDG_RUNTIME_DIR"
if [ ! -e /dev/ptmx ]; then
  mknod /dev/ptmx c 5 2 2>/dev/null || true
  chmod 666 /dev/ptmx 2>/dev/null || true
fi
mount -t devpts devpts /dev/pts -o gid=5,mode=620 2>/dev/null || mount -t devpts devpts /dev/pts 2>/dev/null || true
mount -t tmpfs tmpfs /dev/shm 2>/dev/null || true
hostname alpine 2>/dev/null || true
ip link set lo up 2>/dev/null || true
ip link set eth0 up 2>/dev/null || true
(
  if ! ip route | grep -q default; then
    udhcpc -i eth0 -n -q -t 10 -s /usr/share/udhcpc/default.script || true
  fi
  ts dhcp_done
) &

if [ -x /sbin/udevd ]; then
  /sbin/udevd --daemon 2>/dev/null || true
  udevadm trigger --action=add 2>/dev/null || true
fi
if [ -x /usr/bin/dbus-daemon ]; then
  dbus-uuidgen --ensure 2>/dev/null || true
  dbus-daemon --system 2>/dev/null || true
  dbus-daemon --session --fork --address=unix:path="$XDG_RUNTIME_DIR/bus" 2>/dev/null || true
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi
if command -v seatd >/dev/null && ! pgrep -x seatd >/dev/null; then
  seatd -g root >/tmp/seatd.log 2>&1 &
  ts seatd_started
fi
i=0
while [ ! -e /dev/dri/card0 ] && [ "$i" -lt 40 ]; do
  i=$((i + 1))
  sleep 0.05
done
if [ -e /dev/dri/card0 ] && [ ! -e /dev/dri/renderD128 ]; then
  mknod /dev/dri/renderD128 c 226 128 2>/dev/null || true
fi
chmod 666 /dev/dri/card0 /dev/dri/renderD128 2>/dev/null || true
ts dri_ready
echo "===DESKTOP_START=== $(date) uptime=$(cat /proc/uptime) dri=$(ls /dev/dri 2>/dev/null)" | tee /dev/ttyS0

# Fault Firefox's large libraries into the page cache while labwc starts.
# This is I/O only; it does not pre-JIT libxul for a later process.
(
  for f in /usr/lib/firefox/libxul.so /usr/lib/firefox/*.so; do
    [ -f "$f" ] && cat "$f" >/dev/null 2>&1
  done
) &

# Same bwrap stand-in as the XFCE path: glycin's sandbox hangs in UML.
if [ ! -x /usr/local/bin/bwrap-passthrough.sh ] && [ -x /usr/bin/bwrap ]; then
  :
fi
if [ -e /usr/bin/bwrap ] && [ ! -e /usr/bin/bwrap.real ] && [ -x /usr/local/bin/bwrap-passthrough.sh ]; then
  cp -a /usr/bin/bwrap /usr/bin/bwrap.real 2>/dev/null || true
  cp /usr/local/bin/bwrap-passthrough.sh /usr/bin/bwrap
  chmod 755 /usr/bin/bwrap
fi

mkdir -p /tmp/labwc-cfg
: > /tmp/labwc-cfg/autostart
export WLR_BACKENDS="${WLR_BACKENDS:-drm}"
ts labwc_exec
labwc -C /tmp/labwc-cfg > /tmp/labwc.log 2>&1 &
LBPID=$!
j=0
sock=""
while [ "$j" -lt 80 ]; do
  for s in "$XDG_RUNTIME_DIR"/wayland-*; do
    if [ -S "$s" ]; then
      sock=$s
      break
    fi
  done
  if [ -n "$sock" ]; then
    break
  fi
  if ! kill -0 "$LBPID" 2>/dev/null; then
    ts labwc_died
    cat /tmp/labwc.log | tee /dev/ttyS0
    break
  fi
  j=$((j + 1))
  sleep 0.05
done
if [ -z "$sock" ]; then
  echo "===DESKTOP_FAILED=== labwc no wayland socket" | tee /dev/ttyS0
  cat /tmp/labwc.log | tee /dev/ttyS0
  sleep 3600
  exit 1
fi
export WAYLAND_DISPLAY=${sock##*/}
ts "labwc_socket j=$j WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "===DESKTOP_READY=== $(date) uptime=$(cat /proc/uptime) display=$WAYLAND_DISPLAY labwc=1" | tee /dev/ttyS0
READY_UP=$(up)

if [ -x /usr/local/bin/firefox-kernarium-profile.sh ]; then
  /usr/local/bin/firefox-kernarium-profile.sh
  ts profile_ready
fi
if command -v firefox >/dev/null; then
  echo "===FIREFOX_START=== $(date) uptime=$(cat /proc/uptime) from_ready=0.00" | tee /dev/ttyS0
  ff_profile=""
  if [ -d /root/.mozilla/firefox/kernarium ]; then
    ff_profile="--profile /root/.mozilla/firefox/kernarium"
  fi
  MOZ_ENABLE_WAYLAND=1 MOZ_ACCELERATED=1 \
    firefox $ff_profile --new-instance "https://example.com" \
    > /tmp/firefox.log 2>&1 &
fi
if [ -x /usr/local/bin/desktop-ready.sh ]; then
  # desktop-ready is X11-oriented (xdotool / glxgears); skip it on Wayland.
  :
fi
wait "$LBPID"
