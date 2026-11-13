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
#
# The production overlay mounts the ext4 image read-only as the lower layer
# (UML_BOOT_UPPER=tmpfs). A dirty journal (INCOMPAT_RECOVER) cannot be
# replayed on that mount and panics with UML_BOOT_ERROR:cannot mount /dev/ubda.
# This launcher refuses a dirty-journal image. A clean but mode-0444 image
# is copied (APFS clone when possible) to a writable sibling *.rw.ext4 so a
# later dirty snapshot is not silently reused; set UML_ROOTFS to override.
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
if [ -n "${UML_ROOTFS:-}" ]; then
	ROOTFS=$UML_ROOTFS
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

# Exit 0 = clean ext4, 1 = dirty journal, 2 = unreadable / not ext4.
rootfs_journal_state() {
	/usr/bin/python3 - "$1" << 'PY'
import struct, sys
path = sys.argv[1]
try:
    with open(path, "rb") as fh:
        fh.seek(1024)
        sb = fh.read(1024)
except OSError:
    sys.exit(2)
if len(sb) < 0x64 + 4:
    sys.exit(2)
magic = struct.unpack_from("<H", sb, 0x38)[0]
if magic != 0xEF53:
    sys.exit(2)
incompat = struct.unpack_from("<I", sb, 0x60)[0]
sys.exit(1 if (incompat & 0x4) else 0)
PY
}

prepare_rootfs() {
	local src=$1 dest mode state
	if [ ! -f "$src" ]; then
		echo "rootfs missing: $src" >&2
		return 1
	fi
	state=0
	if rootfs_journal_state "$src"; then
		state=0
	else
		state=$?
	fi
	if [ "$state" -eq 1 ]; then
		echo "REFUSE: $src has a dirty ext4 journal (INCOMPAT_RECOVER)." >&2
		echo "The production overlay mounts this image read-only as /lower, so" >&2
		echo "the kernel cannot replay the journal and will panic with:" >&2
		echo "  EXT4-fs: write access unavailable, cannot proceed" >&2
		echo "  UML_BOOT_ERROR:cannot mount /dev/ubda" >&2
		echo "This is not just a 0444 file mode. Make a writable copy, boot it" >&2
		echo "once with UML_BOOT_UPPER=none, remount ro / poweroff, and keep the" >&2
		echo "dirty original aside (see notes/macos-metal-desktop/journal-replay/)." >&2
		return 1
	fi
	if [ "$state" -eq 2 ]; then
		echo "warning: could not read an ext4 superblock on $src" >&2
	fi
	if [ -w "$src" ]; then
		printf '%s\n' "$src"
		return 0
	fi
	mode=$(/usr/bin/stat -f '%Sp' "$src" 2>/dev/null || echo 'not-writable')
	case "$src" in
	*.ext4) dest="${src%.ext4}.rw.ext4" ;;
	*) dest="${src}.rw" ;;
	esac
	if [ -f "$dest" ] && [ -w "$dest" ] &&
	   [ "$(/usr/bin/stat -f '%z' "$dest")" = "$(/usr/bin/stat -f '%z' "$src")" ] &&
	   ! [ "$src" -nt "$dest" ]; then
		if rootfs_journal_state "$dest"; then
			echo "ROOTFS $src is read-only ($mode); reusing writable copy $dest" >&2
			printf '%s\n' "$dest"
			return 0
		fi
		if [ "$?" -eq 1 ]; then
			echo "warning: $dest has a dirty journal; recopying from $src" >&2
		fi
	fi
	echo "ROOTFS $src is read-only ($mode); copying to writable $dest" >&2
	# APFS clone is instant; fall back to a full copy on other volumes.
	if ! /bin/cp -c "$src" "$dest.tmp" 2>/dev/null; then
		if ! /bin/cp "$src" "$dest.tmp"; then
			rm -f "$dest.tmp"
			echo "REFUSE: $src is read-only and could not be copied to $dest." >&2
			echo "Copy it yourself and chmod u+w, then rerun. Booting the" >&2
			echo "read-only file is OK only when the ext4 journal is clean;" >&2
			echo "this launcher still wants a writable working copy." >&2
			return 1
		fi
	fi
	chmod u+w "$dest.tmp"
	mv -f "$dest.tmp" "$dest"
	printf '%s\n' "$dest"
}

[ -x "$BIN" ] || { echo "uml-darwin missing: $BIN" >&2; exit 1; }
[ -f "$ROOTFS" ] || { echo "rootfs missing: $ROOTFS" >&2; exit 1; }
[ -x "$READY" ] && [ -x "$START" ] && [ -f "$BOOTENV" ]
ROOTFS=$(prepare_rootfs "$ROOTFS")

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
# After a reboot, macOS Screen Sharing may already own 5900 (launchd).
# Do not disable it; fall back to 5901 and say so.
if [ "$DISPLAY_MODE" = vnc ]; then
	if netstat -an -p tcp 2>/dev/null | grep -q '\.5900.*LISTEN' ||
	   netstat -anv 2>/dev/null | grep -q '\.5900.*LISTEN'; then
		args+=(--gpu-vnc-port=5901)
		echo "VNC 127.0.0.1:5900 is already in use (often Screen Sharing); using --gpu-vnc-port=5901" >&2
	fi
fi

echo "LAUNCH $(date) bin=$BIN display=$DISPLAY_MODE desktop=$DESKTOP rootfs=$ROOTFS"
echo "LAUNCH_ARGS ${args[*]}"
exec /usr/bin/caffeinate -dims "$BIN" "${args[@]}"
