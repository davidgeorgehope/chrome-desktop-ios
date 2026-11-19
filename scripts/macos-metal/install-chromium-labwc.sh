#!/bin/bash
# Freeze the clean 0444 labwc image, APFS-clone a writable work copy, and
# apk-add Alpine chromium with UML_BOOT_UPPER=none so writes persist.
# Does not overwrite alpine-3.24.2-desktop-labwc.ext4.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export LANG=C

DIR=/Volumes/KernariumCS/rootfs/starter-20261112
SRC="$DIR/alpine-3.24.2-desktop-labwc.ext4"
FREEZE="$DIR/alpine-3.24.2-desktop-labwc-pre-chromium-20261113.ext4"
WORK="$DIR/alpine-3.24.2-desktop-labwc-chromium-20261113.ext4"
BIN="${UML_DARWIN_BIN:-$HOME/linux-ios-bakeoff/src/Kernarium/.build/presets/macos-integration/bin/uml-darwin-official-c134a87}"
NOTES=$HOME/linux-ios-bakeoff/notes/macos-metal-desktop
FAST=$HOME/linux-ios-bakeoff/notes/desktop-guest-fast
BOOTENV="$FAST/boot.env-upper-none"
INSTALL="$FAST/install-chromium.sh"
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$NOTES/install-chromium-labwc-$STAMP.log"

journal_ok() {
	/usr/bin/python3 - "$1" << 'PY'
import struct, sys
path = sys.argv[1]
with open(path, "rb") as fh:
    fh.seek(1024)
    sb = fh.read(1024)
if len(sb) < 0x64 + 4:
    sys.exit(2)
magic = struct.unpack_from("<H", sb, 0x38)[0]
incompat = struct.unpack_from("<I", sb, 0x60)[0]
sys.exit(1 if magic != 0xEF53 or (incompat & 0x4) else 0)
PY
}

[ -f "$SRC" ] || { echo "missing $SRC"; exit 1; }
[ -x "$BIN" ] || { echo "missing $BIN"; exit 1; }
[ -f "$BOOTENV" ] || { echo "missing $BOOTENV"; exit 1; }
[ -x "$INSTALL" ] || { echo "missing $INSTALL"; exit 1; }
journal_ok "$SRC" || { echo "REFUSE: $SRC journal dirty or unreadable"; exit 1; }
mkdir -p "$NOTES" "$FAST"

{
	echo "INSTALL_CHROMIUM $(date) src=$SRC"
	ls -li "$SRC" "$BIN"
	md5 -q "$BIN"
	sysctl vm.swapusage
} | tee "$LOG"

if [ ! -f "$FREEZE" ]; then
	echo "FREEZE clone $FREEZE" | tee -a "$LOG"
	/bin/cp -c "$SRC" "$FREEZE"
	chmod 0444 "$FREEZE"
fi
if [ ! -f "$WORK" ]; then
	echo "WORK clone $WORK" | tee -a "$LOG"
	/bin/cp -c "$SRC" "$WORK"
	chmod u+w "$WORK"
fi
journal_ok "$WORK" || { echo "REFUSE: $WORK journal dirty"; exit 1; }

unset UML_JIT_PERSISTENT_CACHE UML_JIT_PERSISTENT_CACHE_SOURCE
unset KERNARIUM_JIT_PERSISTENT_CACHE KERNARIUM_JIT_PERSISTENT_CACHE_SOURCE
unset UML_JIT_CACHE_BUDGET

set +e
/usr/bin/script -q -F "$LOG" /usr/bin/caffeinate -i "$BIN" \
	--execution-engine=jit \
	--guest-file=/boot.env="$BOOTENV" \
	--guest-file=/payload/usr/local/bin/start-desktop.sh="$INSTALL" \
	mem=2G ncpus=4 \
	ubd0c="$WORK" \
	rootfstype=ext4
status=$?
set -e
echo "STOPPED $(date) status=$status" | tee -a "$LOG"
sysctl vm.swapusage | tee -a "$LOG"

if journal_ok "$WORK"; then
	echo "JOURNAL clean $WORK" | tee -a "$LOG"
	chmod 0444 "$WORK"
	ls -li "$SRC" "$FREEZE" "$WORK" | tee -a "$LOG"
else
	echo "JOURNAL dirty or unreadable after install; left writable $WORK" | tee -a "$LOG"
	exit 1
fi
echo LOG="$LOG"
exit 0
