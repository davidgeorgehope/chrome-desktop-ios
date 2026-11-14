#!/bin/sh
# Inject a real touch/click, then KEY_A, via the UML VNC evdev nodes.
set -eu

evdev_le16() { printf "\\$(printf '%03o' $(($1 & 255)))\\$(printf '%03o' $((($1 >> 8) & 255)))"; }
evdev_le32() {
  printf "\\$(printf '%03o' $(($1 & 255)))\\$(printf '%03o' $((($1 >> 8) & 255)))"
  printf "\\$(printf '%03o' $((($1 >> 16) & 255)))\\$(printf '%03o' $((($1 >> 24) & 255)))"
}
evdev_event() {
  printf '\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0'
  evdev_le16 "$1"
  evdev_le16 "$2"
  evdev_le32 "$3"
}

report() { echo "$*" | tee /dev/ttyS0; }

if [ -f /proc/bus/input/devices ]; then
  report "===INTERACTIVE_EVDEV_DEVICES==="
  cat /proc/bus/input/devices | tee /dev/ttyS0
fi

kbd=""
tablet=""
if [ -f /proc/bus/input/devices ]; then
  kbd=$(awk '
    BEGIN { FS="\n"; RS=""; }
    /VNC Keyboard|Name=".*[Kk]eyboard/ {
      for (i=1;i<=NF;i++) if (match($i, /event[0-9]+/)) {
        print "/dev/input/" substr($i, RSTART, RLENGTH); exit
      }
    }
  ' /proc/bus/input/devices)
  tablet=$(awk '
    BEGIN { FS="\n"; RS=""; }
    /VNC Tablet|Name=".*[Tt]ablet|Name=".*[Tt]ouchscreen/ {
      for (i=1;i<=NF;i++) if (match($i, /event[0-9]+/)) {
        print "/dev/input/" substr($i, RSTART, RLENGTH); exit
      }
    }
  ' /proc/bus/input/devices)
fi
[ -z "$kbd" ] && [ -e /dev/input/event0 ] && kbd=/dev/input/event0
[ -z "$tablet" ] && [ -e /dev/input/event1 ] && tablet=/dev/input/event1
# Kernarium iOS/D4iPad/Sim expose a virtio multitouch "Kernarium
# Touchscreen" (ABS 0..32767, MT slots) instead of the VNC tablet
# (ABS 0..65535). Halve coordinates and add MT events there; the kernel
# drops MT codes a device does not advertise, so the VNC path is unchanged.
touch_mt=0
if [ -n "$tablet" ] && grep -q 'Kernarium Touchscreen' /proc/bus/input/devices 2>/dev/null; then
  case "$(cat /sys/class/input/${tablet##*/}/device/name 2>/dev/null)" in
    *Touchscreen*) touch_mt=1 ;;
  esac
fi
report "===INTERACTIVE_EVDEV_POKE=== kbd=$kbd tablet=$tablet touch_mt=$touch_mt"

write_blob() {
  dev=$1
  file=$2
  chmod 666 "$dev" 2>/dev/null || true
  if [ ! -e "$dev" ]; then
    report "===INTERACTIVE_EVDEV_WRITE=== dev=$dev why=missing"
    return 1
  fi
  if [ ! -w "$dev" ]; then
    report "===INTERACTIVE_EVDEV_WRITE=== dev=$dev why=not_writable $(ls -l "$dev" 2>/dev/null)"
    return 1
  fi
  bytes=$(wc -c < "$file")
  dd if="$file" of="$dev" bs="$bytes" count=1 2>/tmp/evdev-dd.err
  st=$?
  report "===INTERACTIVE_EVDEV_WRITE=== dev=$dev rc=$st bytes=$bytes dd=$(tr '\n' ' ' < /tmp/evdev-dd.err)"
  return $st
}

# One click at a 16-bit ABS point. 960,540 (1920x1080 mid) produced no
# mousedown; the VNC tablet's range is 0..65535 (PROP=2 / ABS=3).
# BTN_TOUCH=330, BTN_LEFT=272, ABS_X=0, ABS_Y=1, SYN_REPORT=0.
click_at() {
  x=$1
  y=$2
  tmp=/tmp/evdev-touch.bin
  if [ "$touch_mt" = 1 ]; then
    x=$((x / 2)); y=$((y / 2))
    # BTN_TOUCH first, then ABS_MT_SLOT(0x2f) / TRACKING_ID(0x39) /
    # POSITION_X(0x35) / POSITION_Y(0x36), mirroring touchscreen.cpp.
    {
      evdev_event 1 330 1
      evdev_event 3 47 0
      evdev_event 3 57 1
      evdev_event 3 53 "$x"
      evdev_event 3 54 "$y"
      evdev_event 3 0 "$x"
      evdev_event 3 1 "$y"
      evdev_event 0 0 0
      evdev_event 1 330 0
      evdev_event 3 47 0
      evdev_event 3 57 -1
      evdev_event 3 0 "$x"
      evdev_event 3 1 "$y"
      evdev_event 0 0 0
    } > "$tmp"
    write_blob "$tablet" "$tmp" || true
    return 0
  fi
  {
    evdev_event 3 0 "$x"
    evdev_event 3 1 "$y"
    evdev_event 0 0 0
    evdev_event 1 330 1
    evdev_event 1 272 1
    evdev_event 0 0 0
    evdev_event 1 272 0
    evdev_event 1 330 0
    evdev_event 0 0 0
  } > "$tmp"
  write_blob "$tablet" "$tmp" || true
}

if [ -n "$tablet" ]; then
  # Focus first: a default Firefox window often sits in the upper half,
  # so a mid-screen click can miss it and steal focus to the desktop.
  # Upper-center (~30% down), then mid, then the mid click that should
  # hit maximized content. Chromium already worked with mid alone.
  report "===INTERACTIVE_EVDEV_FOCUS=== upper then mid"
  click_at 32767 19660
  sleep 0.25
  click_at 32767 32767
  sleep 0.35
fi

if [ -n "$kbd" ]; then
  tmp=/tmp/evdev-key.bin
  {
    evdev_event 1 30 1
    evdev_event 0 0 0
    evdev_event 1 30 0
    evdev_event 0 0 0
  } > "$tmp"
  write_blob "$kbd" "$tmp" || true
  sleep 0.3
  write_blob "$kbd" "$tmp" || true
fi
