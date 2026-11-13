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
    /VNC Tablet|Name=".*[Tt]ablet/ {
      for (i=1;i<=NF;i++) if (match($i, /event[0-9]+/)) {
        print "/dev/input/" substr($i, RSTART, RLENGTH); exit
      }
    }
  ' /proc/bus/input/devices)
fi
[ -z "$kbd" ] && [ -e /dev/input/event0 ] && kbd=/dev/input/event0
[ -z "$tablet" ] && [ -e /dev/input/event1 ] && tablet=/dev/input/event1
report "===INTERACTIVE_EVDEV_POKE=== kbd=$kbd tablet=$tablet"

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

if [ -n "$tablet" ]; then
  tmp=/tmp/evdev-touch.bin
  {
    # One click at 16-bit ABS mid. 960,540 (1920x1080 mid) produced no
    # mousedown; the VNC tablet's range is 0..65535 (PROP=2 / ABS=3).
    # BTN_TOUCH=330, BTN_LEFT=272, ABS_X=0, ABS_Y=1, SYN_REPORT=0.
    evdev_event 3 0 32767
    evdev_event 3 1 32767
    evdev_event 0 0 0
    evdev_event 1 330 1
    evdev_event 1 272 1
    evdev_event 0 0 0
    evdev_event 1 272 0
    evdev_event 1 330 0
    evdev_event 0 0 0
  } > "$tmp"
  write_blob "$tablet" "$tmp" || true
  sleep 0.5
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
