#!/bin/bash
# Pack an ext4 rootfs to .gz only after the journal is clean.
#
# The production overlay (UML_BOOT_UPPER=tmpfs) mounts the image read-only as
# /lower. A dirty journal (INCOMPAT_RECOVER) cannot be replayed on a ro mount
# and panics with UML_BOOT_ERROR:cannot mount /dev/ubda. The 13 Nov 2026 labwc
# and desktop-fast Drive images were snapshotted that way: the guest install
# used `poweroff -f`, and the host gzipped the ext4 without e2fsck.
#
# Usage: pack-rootfs-gz.sh [--gzip-level N] image.ext4 [image.ext4.gz]
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/opt/homebrew/opt/e2fsprogs/sbin

LEVEL=1
if [ "${1:-}" = "--gzip-level" ]; then
	LEVEL="$2"
	shift 2
fi
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ $# -lt 1 ]; then
	echo "usage: $0 [--gzip-level N] image.ext4 [image.ext4.gz]" >&2
	exit 2
fi

SRC=$1
if [ $# -ge 2 ]; then
	DST=$2
else
	DST=${SRC}.gz
fi
if [ ! -f "$SRC" ]; then
	echo "error: no such file: $SRC" >&2
	exit 1
fi

# Return 0 if INCOMPAT_RECOVER (0x4) is set. Superblock is at offset 1024;
# s_feature_incompat is at 0x60 in the superblock (little-endian u32).
journal_dirty() {
	python3 - "$1" << 'PY'
import struct, sys
from pathlib import Path
p = Path(sys.argv[1])
data = p.read_bytes()[:2048]
if len(data) < 1024 + 0x64:
    sys.stderr.write("error: %s is too small to be an ext4 image\n" % p)
    sys.exit(2)
magic = struct.unpack_from("<H", data, 1024 + 0x38)[0]
if magic != 0xEF53:
    sys.stderr.write("error: %s is not an ext4 superblock (magic=0x%04x)\n" % (p, magic))
    sys.exit(2)
incompat = struct.unpack_from("<I", data, 1024 + 0x60)[0]
sys.exit(0 if (incompat & 0x4) else 1)
PY
}

run_e2fsck() {
	local img=$1
	if command -v e2fsck >/dev/null 2>&1; then
		echo "e2fsck (host): $img"
		e2fsck -fy "$img" || true
		return 0
	fi
	if command -v limactl >/dev/null 2>&1 && limactl list -q 2>/dev/null | grep -qx kernarium-linux; then
		# e2fsck of a file does not need a loop mount. Copy onto Lima's
		# own disk first: virtiofs has bitten rw loop-mounts before.
		echo "e2fsck (lima kernarium-linux): $img"
		limactl shell kernarium-linux -- sudo -n bash -c "
			set -euo pipefail
			src=\$(printf '%s' $(printf '%q' "$img"))
			work=/home/guest/pack-rootfs-e2fsck.ext4
			cp -f \"\$src\" \"\$work\"
			sync
			e2fsck -fy \"\$work\" || true
			cp -f \"\$work\" \"\$src\"
			sync
			rm -f \"\$work\"
		"
		return 0
	fi
	return 1
}

if journal_dirty "$SRC"; then
	echo "WARN: $SRC has a dirty ext4 journal (INCOMPAT_RECOVER); repairing before gzip" >&2
	if ! run_e2fsck "$SRC"; then
		echo "error: $SRC is dirty and no e2fsck is available (install e2fsprogs, or replay the journal with a rw UML mount, then retry)." >&2
		exit 1
	fi
	if journal_dirty "$SRC"; then
		echo "error: $SRC still has INCOMPAT_RECOVER after e2fsck" >&2
		exit 1
	fi
	echo "journal clean after e2fsck"
else
	echo "journal clean (no INCOMPAT_RECOVER)"
fi

# Flush any writer that still has the image open, then compress.
sync
echo "gzip -$LEVEL $SRC -> $DST"
gzip -n -c -"$LEVEL" "$SRC" > "$DST.tmp"
mv -f "$DST.tmp" "$DST"
# SHA-256 of the gzip payload and of the uncompressed ext4.
if command -v sha256sum >/dev/null 2>&1; then
	sha256sum "$DST" "$SRC"
elif command -v shasum >/dev/null 2>&1; then
	shasum -a 256 "$DST" "$SRC"
fi
echo "PACK_OK $DST"
