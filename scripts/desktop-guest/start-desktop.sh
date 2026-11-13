#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export USER=root
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp/runtime-root
export XDG_SESSION_TYPE=x11
export LANG=C.UTF-8
# Prefer the virtio-gpu gallium path (host virgl) over guest llvmpipe.
export MESA_LOADER_DRIVER_OVERRIDE=virtio_gpu
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
# A render node is what Mesa uses for virgl. Create it if udev did not.
if [ -e /dev/dri/card0 ] && [ ! -e /dev/dri/renderD128 ]; then
  mknod /dev/dri/renderD128 c 226 128 2>/dev/null || true
fi
chmod 666 /dev/dri/card0 /dev/dri/renderD128 2>/dev/null || true
echo "===DESKTOP_START=== $(date) uptime=$(cat /proc/uptime) dri=$(ls /dev/dri 2>/dev/null) drm=$(ls /sys/class/drm 2>/dev/null)" | tee /dev/ttyS0
ls -l /dev/dri /sys/class/drm 2>/dev/null | tee /dev/ttyS0
run_xfce() {
  command -v startxfce4 >/dev/null && command -v Xorg >/dev/null || return 1
  mkdir -p /etc/X11/xorg.conf.d /root/.config/xfce4 /root/.config/autostart
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
  cat > /root/.config/autostart/bakeoff.desktop << 'EOD'
[Desktop Entry]
Type=Application
Name=Bakeoff session hooks
Exec=/usr/local/bin/desktop-ready.sh
X-GNOME-Autostart-enabled=true
EOD
  echo "trying XFCE/Xorg" | tee /dev/ttyS0
  exec startx /usr/bin/startxfce4 -- :0 vt1
}
run_xfce
echo "===DESKTOP_FAILED=== no compositor" | tee /dev/ttyS0
sleep 3600
