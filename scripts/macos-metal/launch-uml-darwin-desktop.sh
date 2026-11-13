#!/bin/bash
# Launch the Alpine desktop on the native macOS uml-darwin CLI with
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
#
# Default session is labwc (DESKTOP_READY ~2.5 s). UML_DESKTOP=xfce selects
# the sessionless XFCE path (~8.7 s READY).
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export LANG=C

ROOT=/Users/davidhope/linux-ios-bakeoff/src/Kernarium
NOTES=/Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop
FAST=/Users/davidhope/linux-ios-bakeoff/notes/desktop-guest-fast
BIN="$ROOT/.build/presets/macos-integration/bin/uml-darwin"
if [ ! -x "$BIN" ]; then
	BIN="$ROOT/.build/macos-integration/bin/uml-darwin"
fi
ROOTFS=/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-desktop.ext4
# Prefer the labwc-baked image when present; fall back to the original XFCE image.
if [ -f /Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-desktop-labwc.ext4 ]; then
	ROOTFS=/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-desktop-labwc.ext4
fi
READY="$FAST/desktop-ready.sh"
BWRAP="$FAST/bwrap-passthrough.sh"
FFPROF="$FAST/firefox-kernarium-profile.sh"
DESKTOP="${UML_DESKTOP:-labwc}"
if [ "$DESKTOP" = xfce ]; then
	START="$FAST/start-desktop.sh"
else
	START="$FAST/start-desktop-labwc.sh"
fi
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
if [ -x "$BWRAP" ]; then
	args+=( --guest-file=/payload/usr/local/bin/bwrap-passthrough.sh="$BWRAP" )
fi
# Optional larger host JIT budget so Firefox unique translations stay in
# the shared cache. Default leftover at mem=4G ncpus=8 is 3 GiB and fills
# mid-session; 8G total leaves ~6 GiB shared. Evict-on-full (patches/0011)
# needs a rebuilt uml-darwin; the flag itself works on the official binary.
if [ -n "${UML_JIT_CACHE_BUDGET:-}" ]; then
	args+=( --jit-cache-budget="$UML_JIT_CACHE_BUDGET" )
fi
if [ -x "$FFPROF" ]; then
	args+=( --guest-file=/payload/usr/local/bin/firefox-kernarium-profile.sh="$FFPROF" )
fi
if [ "$DISPLAY_MODE" = native ]; then
	args+=( --gpu-auto-resize=off )
fi

echo "LAUNCH $(date) bin=$BIN display=$DISPLAY_MODE desktop=$DESKTOP rootfs=$ROOTFS"
echo "LAUNCH_ARGS ${args[*]}"
exec /usr/bin/caffeinate -dims "$BIN" "${args[@]}"
