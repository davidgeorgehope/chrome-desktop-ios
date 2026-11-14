#!/bin/bash
# Usage: bake-ios-interactive-image.sh BASE_NAME OUT_NAME firefox|chromium
# (R=dir overrides the rootfs dir.) APFS-clones BASE to OUT and boots official
# 0022 once with UML_BOOT_UPPER=none so the interactive harness, Chromium
# flags and Firefox maximize profile land on the ext4. The guest script is
# notes/ios-interactive/bake-guest.sh on the mini (repo: bake-ios-interactive-guest.sh).
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
D=/Users/davidhope/linux-ios-bakeoff/notes/ios-interactive
R=${R:-/Volumes/KernariumCS/rootfs/starter-20261112}
G=$D/desktop-guest
M=$G/interactive-metrics
FAST=/Users/davidhope/linux-ios-bakeoff/notes/desktop-guest-fast
BIN=/Users/davidhope/linux-ios-bakeoff/src/Kernarium/.build/presets/macos-integration/bin/uml-darwin-official-0022-20261113
[ "$(md5 -q "$BIN")" = 6ea8180e05fc6736d32530811ba3c439 ] || { echo "official md5 mismatch"; exit 2; }
BASE=$R/$1; OUT=$R/$2; BROWSER=$3
[ -e "$OUT" ] && { echo "refuse: $OUT exists"; exit 2; }
cp -c "$BASE" "$OUT"; chmod 644 "$OUT"
echo 1 > $D/flag; printf '%s\n' "$BROWSER" > $D/browser-$BROWSER
export UML_PREFLIGHT_GUEST_MEM=2G
. /Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop/preflight-uml-darwin.sh
LOG=$D/bake-$2-$(date +%Y%m%d-%H%M%S).log
/usr/bin/script -q "$LOG" "$BIN" --execution-engine=jit --gpu-display=native --gpu-width=1920 --gpu-height=1080 --gpu-auto-resize=off \
  --guest-file=/boot.env=$D/boot.env-upper-none \
  --guest-file=/payload/usr/local/bin/start-desktop.sh=$D/bake-guest.sh \
  --guest-file=/payload/usr/local/bin/good-start-desktop.sh=$G/start-desktop-labwc.sh \
  --guest-file=/payload/usr/local/bin/desktop-ready.sh=$FAST/desktop-ready.sh \
  --guest-file=/payload/usr/local/bin/bwrap-passthrough.sh=$G/bwrap-passthrough.sh \
  --guest-file=/payload/usr/local/bin/firefox-kernarium-profile.sh=$G/firefox-kernarium-profile.sh \
  --guest-file=/payload/usr/local/bin/interactive-metrics-start.sh=$G/interactive-metrics-start.sh \
  --guest-file=/payload/usr/local/etc/interactive-metrics=$D/flag \
  --guest-file=/payload/usr/local/etc/desktop-browser=$D/browser-$BROWSER \
  --guest-file=/payload/usr/local/etc/chromium-flags=$G/chromium-flags \
  --guest-file=/payload/usr/local/share/interactive-metrics/index.html=$M/index.html \
  --guest-file=/payload/usr/local/share/interactive-metrics/warm.html=$M/warm.html \
  --guest-file=/payload/usr/local/share/interactive-metrics/cgi-bin/report=$M/cgi-bin/report \
  --guest-file=/payload/usr/local/share/interactive-metrics/metrics-httpd=$M/metrics-httpd \
  --guest-file=/payload/usr/local/share/interactive-metrics/evdev-poke.sh=$M/evdev-poke.sh \
  mem=2G ubd0c="$OUT" < /dev/null > /dev/null 2>&1 &
UPID=$!
for i in $(seq 1 150); do kill -0 $UPID 2>/dev/null || break; sleep 1; done
if kill -0 $UPID 2>/dev/null; then echo "TIMEOUT: TERM"; pkill -TERM -f "[u]ml-darwin-official-0022-20261113" || true; sleep 5; pkill -KILL -f "[u]ml-darwin-official-0022-20261113" || true; fi
wait $UPID 2>/dev/null || true
grep -a -E '===BAKE|browser=' "$LOG" | tr -d '\r' | sort -u
python3 - "$OUT" << 'PY'
import struct,sys
sb=open(sys.argv[1],'rb'); sb.seek(1024); b=sb.read(1024)
inc=struct.unpack_from('<I',b,0x60)[0]; print('incompat=%#x dirty=%s'%(inc, bool(inc&4)))
PY
chmod 444 "$OUT"
echo "LOG=$LOG"
