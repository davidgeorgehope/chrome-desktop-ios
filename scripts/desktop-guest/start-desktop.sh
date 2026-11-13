#!/bin/sh
# Fast XFCE session for UML/Darwin.
#
# Root cause of the old ~20 s xfwm4 stall (gdb, 13 Nov 2026): libglycin's
# gly-hdl-loader thread blocked in do_wait on a hung `bwrap --unshare-all`
# child. UML does not provide the namespaces that sandbox expects. It is not
# fc-cache (already present in the image), xfconf, or GPU/vblank-specific
# (llvmpipe shows the same class of delay on the original startxfce4 path).
#
# Mitigations, applied here:
# - Replace /usr/bin/bwrap with a POSIX passthrough (real binary saved as
#   /usr/bin/bwrap.real) so later glycin use can run without unshare/seccomp.
# - Hide /usr/share/glycin-loaders only until the window manager advertises
#   _NET_SUPPORTING_WM_CHECK, then restore it so Firefox can still decode
#   images. Do not remove libglycin or stub the loaders (those add GTK
#   pixbuf timeouts).
# - Start the session without xfce4-session (avoids serialized SM timeouts).
# - xfwm4 --compositor=off --vblank=off.
# - Disable at-spi, gnome-keyring and xfce4-power-manager autostarts.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export USER=root
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-root
export XDG_SESSION_TYPE=x11
export LANG=C.UTF-8
export NO_AT_BRIDGE=1
export GTK_A11Y=none
export GIO_USE_VFS=local
export GVFS_DISABLE_FUSE=1
# Do not force MESA_LOADER_DRIVER_OVERRIDE. On the Simulator host this session
# uses guest virgl (host llvmpipe). On Designed for iPad / a device host with
# Venus, desktop-ready.sh prefers guest Zink over virtio-vulkan / KosmicKrisp.
unset MESA_LOADER_DRIVER_OVERRIDE
export LIBGL_ALWAYS_SOFTWARE=0
mkdir -p "$XDG_RUNTIME_DIR" /run/dbus /var/run /tmp /var/log
chmod 700 "$XDG_RUNTIME_DIR"
mkdir -p /dev/pts /dev/shm
if [ ! -e /dev/ptmx ]; then
  mknod /dev/ptmx c 5 2 2>/dev/null || true
  chmod 666 /dev/ptmx 2>/dev/null || true
fi
mount -t devpts devpts /dev/pts -o gid=5,mode=620 2>/dev/null || mount -t devpts devpts /dev/pts 2>/dev/null || true
mount -t tmpfs tmpfs /dev/shm 2>/dev/null || true
hostname alpine 2>/dev/null || true
ip link set lo up 2>/dev/null || true
ip link set eth0 up 2>/dev/null || true
if ! ip route | grep -q default; then
  udhcpc -i eth0 -n -q -t 10 -s /usr/share/udhcpc/default.script || true
fi
if [ -x /sbin/udevd ]; then
  /sbin/udevd --daemon 2>/dev/null || true
  udevadm trigger --action=add 2>/dev/null || true
  udevadm settle --timeout=8 2>/dev/null || true
fi
if [ -x /usr/bin/dbus-daemon ]; then
  dbus-uuidgen --ensure 2>/dev/null || true
  dbus-daemon --system 2>/dev/null || true
  dbus-daemon --session --fork --address=unix:path="$XDG_RUNTIME_DIR/bus" 2>/dev/null || true
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi
i=0
while [ ! -e /dev/dri/card0 ] && [ "$i" -lt 40 ]; do
  i=$((i + 1))
  sleep 0.2
done
# A render node is what Mesa uses for virgl/zink. Create it if udev did not.
if [ -e /dev/dri/card0 ] && [ ! -e /dev/dri/renderD128 ]; then
  mknod /dev/dri/renderD128 c 226 128 2>/dev/null || true
fi
chmod 666 /dev/dri/card0 /dev/dri/renderD128 2>/dev/null || true

up() { awk '{print $1}' /proc/uptime; }
echo "===DESKTOP_START=== $(date) uptime=$(cat /proc/uptime) dri=$(ls /dev/dri 2>/dev/null) drm=$(ls /sys/class/drm 2>/dev/null)" | tee /dev/ttyS0
ls -l /dev/dri /sys/class/drm 2>/dev/null | tee /dev/ttyS0

# Install a bwrap stand-in that skips unshare/seccomp and execs the first
# absolute executable in argv. UML/Darwin has no working glycin sandbox.
if [ ! -x /usr/local/bin/bwrap-passthrough.sh ]; then
  cat > /usr/local/bin/bwrap-passthrough.sh << 'EOB'
#!/bin/sh
# Run the command bubblewrap would have launched, without unshare/seccomp.
# UML/Darwin does not provide the namespaces glycin's sandbox expects.
while [ "$#" -gt 0 ]; do
  a=$1
  case "$a" in
    --chdir|--uid|--gid|--hostname|--seccomp|--exec-label|--file-label|--lock-file|--sync-fd|--info-fd|--json-status-fd|--cap-add|--cap-drop|--pidns-fd|--userns|--userns-block-fd|--userns-fd|--dir|--size|--perms|--dev|--proc|--tmpfs|--mqueue|--remount-ro|--bind-data|--ro-bind-data|--overlay-src)
      shift 2 2>/dev/null || shift
      continue
      ;;
    --ro-bind|--ro-bind-try|--bind|--bind-try|--dev-bind|--dev-bind-try|--symlink|--chmod|--chown|--setenv|--file|--overlay|--tmp-overlay)
      shift 3 2>/dev/null || shift
      continue
      ;;
    --unshare-*|--die-with-parent|--as-pid-1|--new-session|--clearenv|--disable-*|--help|--version|--args|--assert-*)
      shift
      continue
      ;;
    --*=*)
      shift
      continue
      ;;
    /*)
      if [ -f "$a" ] && [ -x "$a" ]; then
        exec "$@"
      fi
      shift
      continue
      ;;
    *)
      shift
      continue
      ;;
  esac
done
echo "bwrap-passthrough: no command in argv" >&2
exit 127
EOB
  chmod 755 /usr/local/bin/bwrap-passthrough.sh
fi
if [ -e /usr/bin/bwrap ] && [ ! -e /usr/bin/bwrap.real ]; then
  cp -a /usr/bin/bwrap /usr/bin/bwrap.real 2>/dev/null || true
fi
cp /usr/local/bin/bwrap-passthrough.sh /usr/bin/bwrap
chmod 755 /usr/bin/bwrap
echo "BWRAP_PASSTHROUGH installed $(up)" | tee /dev/ttyS0

mkdir -p /root/.config/autostart /etc/gtk-3.0 /etc/gtk-4.0 \
  /root/.config/gtk-3.0 /root/.config/gtk-4.0 \
  /root/.config/xfce4/xfconf/xfce-perchannel-xml /etc/X11/xorg.conf.d
for name in at-spi-dbus-bus gnome-keyring-pkcs11 gnome-keyring-secrets xfce4-power-manager; do
  if [ -f "/etc/xdg/autostart/${name}.desktop" ]; then
    printf '%s\n' '[Desktop Entry]' 'Hidden=true' > "/root/.config/autostart/${name}.desktop"
  fi
done

# Prefer a PNG icon theme during WM/panel start so GTK does not wait on SVG
# loaders while glycin is deferred. Adwaita stays the widget theme.
for ini in /etc/gtk-3.0/settings.ini /etc/gtk-4.0/settings.ini \
           /root/.config/gtk-3.0/settings.ini /root/.config/gtk-4.0/settings.ini; do
  cat > "$ini" << 'EOGTK'
[Settings]
gtk-icon-theme-name=hicolor
gtk-theme-name=Adwaita
gtk-font-name=Sans 10
EOGTK
done
cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << 'EOX'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="vblank_mode" type="string" value="off"/>
  </property>
</channel>
EOX
cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << 'EOX'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita"/>
    <property name="IconThemeName" type="string" value="hicolor"/>
  </property>
</channel>
EOX

# Hide glycin loader *config* so libglycin cannot find a loader during WM
# start. Binaries stay in place (ENOENT / stubs add multi-second GTK waits).
mkdir -p /tmp/disabled-glycin-conf
if [ -d /usr/share/glycin-loaders ]; then
  mv /usr/share/glycin-loaders /tmp/disabled-glycin-conf/ 2>/dev/null || true
  echo "GLYCIN_CONF hidden $(up)" | tee /dev/ttyS0
fi

cat > /etc/X11/xorg.conf.d/10-virtio.conf << 'EOX'
Section "Device"
    Identifier "VirtioGPU"
    Driver "modesetting"
    Option "AccelMethod" "glamor"
    Option "SWcursor" "true"
    Option "kmsdev" "/dev/dri/card0"
EndSection
Section "InputClass"
    Identifier "libinput touchscreen"
    MatchIsTouchscreen "on"
    Driver "libinput"
    Option "Tapping" "on"
EndSection
Section "InputClass"
    Identifier "libinput keyboard"
    MatchIsKeyboard "on"
    Driver "libinput"
EndSection
Section "InputClass"
    Identifier "libinput pointer"
    MatchIsPointer "on"
    Driver "libinput"
EndSection
EOX

cat > /usr/local/bin/xfce-fast.sh << 'EOS'
#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DISPLAY="${DISPLAY:-:0}"
export HOME=/root
export USER=root
export NO_AT_BRIDGE=1
export GTK_A11Y=none
export GIO_USE_VFS=local
export GVFS_DISABLE_FUSE=1
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
export XDG_SESSION_TYPE=x11
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi
up() { awk '{print $1}' /proc/uptime; }
if [ -x /usr/lib/xfce4/xfconf/xfconfd ]; then
  /usr/lib/xfce4/xfconf/xfconfd &
  sleep 0.05
fi
echo "XFWM_START $(up)" | tee /dev/ttyS0
xfwm4 --compositor=off --vblank=off --sm-client-disable &
WMPID=$!
i=0
found=0
while [ "$i" -lt 80 ]; do
  wm=$(xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null || true)
  if echo "$wm" | grep -q '0x'; then
    found=1
    echo "XFWM_READY $(up) i=$i wm=$wm" | tee /dev/ttyS0
    break
  fi
  i=$((i + 1))
  sleep 0.2
done
if [ "$found" -eq 0 ]; then
  echo "XFWM_TIMEOUT $(up)" | tee /dev/ttyS0
fi
xfsettingsd --sm-client-disable &
xfce4-panel --disable-wm-check --sm-client-disable &
xfdesktop --disable-wm-check --sm-client-disable &
# Restore glycin loader config now that the WM (and panel) are started, so
# later apps such as Firefox can still decode SVG/PNG through glycin and
# the bwrap passthrough.
if [ -d /tmp/disabled-glycin-conf/glycin-loaders ] && [ ! -d /usr/share/glycin-loaders ]; then
  mv /tmp/disabled-glycin-conf/glycin-loaders /usr/share/glycin-loaders
  echo "GLYCIN_CONF restored $(up)" | tee /dev/ttyS0
fi
echo "===DESKTOP_READY=== $(date) uptime=$(cat /proc/uptime) display=$DISPLAY xfwm_found=$found" | tee /dev/ttyS0
# xwininfo is not in the image; use xprop / process presence.
if pgrep -x xfce4-panel >/dev/null 2>&1; then
  echo "PANEL_PROC $(up)" | tee /dev/ttyS0
fi
clients=$(xprop -root _NET_CLIENT_LIST 2>/dev/null || true)
echo "CLIENT_LIST $(up) $clients" | tee /dev/ttyS0
# Time-to-first-Firefox-page from READY: start immediately, do not wait
# for desktop-ready.sh's vulkan/glxgears/vkcube probes.
if command -v firefox >/dev/null; then
  echo "===FIREFOX_START=== $(date) uptime=$(cat /proc/uptime) from_ready=0.00" | tee /dev/ttyS0
  firefox --new-instance --display="$DISPLAY" "https://example.com" > /tmp/firefox.log 2>&1 &
fi
# Sessionless start skips xfce4-session autostart, so run the bakeoff hook
# ourselves when the launch overlay provided it.
if [ -x /usr/local/bin/desktop-ready.sh ]; then
  /usr/local/bin/desktop-ready.sh &
fi
wait "$WMPID"
EOS
chmod 755 /usr/local/bin/xfce-fast.sh

run_xfce() {
  command -v xfwm4 >/dev/null && command -v Xorg >/dev/null || return 1
  echo "trying XFCE/Xorg (sessionless, glycin deferred)" | tee /dev/ttyS0
  exec startx /usr/local/bin/xfce-fast.sh -- :0 vt1
}
run_xfce
echo "===DESKTOP_FAILED=== no compositor" | tee /dev/ttyS0
sleep 3600
