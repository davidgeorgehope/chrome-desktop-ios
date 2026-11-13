#!/bin/bash
# Launch the Alpine XFCE desktop on the native macOS uml-darwin CLI with
# KosmicKrisp (real Metal on the M-series GPU).
#
# Designed-for-iPad is blocked on this Mac: Xcode 26.6 reports
# "Xcode doesn't support My Mac's macOS 26.3.1 (25D2128)". Do not install
# on a physical iPhone. Do not change the Mac's 3840x2160 display, and do
# not enable voxl resize.
#
# Default CLI display is VNC (127.0.0.1:5900). Set UML_GPU_DISPLAY=native
# (the GUI .command does this) for an AppKit window that screencapture can
# record. Keep the guest framebuffer at 1920x1080.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export LANG=C

ROOT=/Users/davidhope/linux-ios-bakeoff/src/Kernarium
NOTES=/Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop
BIN="$ROOT/.build/presets/macos-integration/bin/uml-darwin"
if [ ! -x "$BIN" ]; then
	BIN="$ROOT/.build/macos-integration/bin/uml-darwin"
fi
ROOTFS=/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-desktop.ext4
READY=/Users/davidhope/linux-ios-bakeoff/notes/desktop-guest-fast/desktop-ready.sh
START=/Users/davidhope/linux-ios-bakeoff/notes/desktop-guest-fast/start-desktop.sh
BOOTENV="$NOTES/boot.env"
DISPLAY_MODE="${UML_GPU_DISPLAY:-vnc}"

[ -x "$BIN" ] || { echo "uml-darwin missing: $BIN" >&2; exit 1; }
[ -f "$ROOTFS" ] || { echo "rootfs missing: $ROOTFS" >&2; exit 1; }
[ -x "$READY" ] && [ -x "$START" ] && [ -f "$BOOTENV" ]

args=(
	--execution-engine=jit
	--gpu-display="$DISPLAY_MODE"
	--gpu-width=1920
	--gpu-height=1080
	--guest-file=/boot.env="$BOOTENV"
	--guest-file=/payload/usr/local/bin/desktop-ready.sh="$READY"
	--guest-file=/payload/usr/local/bin/start-desktop.sh="$START"
	mem=4G
	ncpus=8
	ubd0c="$ROOTFS"
	rootfstype=ext4
)
if [ "$DISPLAY_MODE" = native ]; then
	args+=( --gpu-auto-resize=off )
fi

echo "LAUNCH $(date) bin=$BIN display=$DISPLAY_MODE"
echo "LAUNCH_ARGS ${args[*]}"
exec /usr/bin/caffeinate -dims "$BIN" "${args[@]}"
