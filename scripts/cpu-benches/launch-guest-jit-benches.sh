#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export LANG=C
ROOT=$HOME/linux-ios-bakeoff/src/Kernarium
BIN="$ROOT/.build/presets/macos-integration/bin/uml-darwin"
NOTES=$HOME/linux-ios-bakeoff/notes
PACK="$NOTES/cpu-benches"
ROOTFS=/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-minimal.ext4
[ -x "$BIN" ] || { echo "missing uml-darwin"; exit 1; }
[ -f "$ROOTFS" ] || { echo "missing rootfs"; exit 1; }
echo "LAUNCH $(date) jit cpu benches mem=2G ncpus=8 no-gpu"
extra=()
if [ -f "$PACK/apks.tar" ]; then
  extra+=(--guest-file=/payload/usr/local/share/cpu-benches/apks.tar="$PACK/apks.tar")
fi
exec /usr/bin/caffeinate -i "$BIN" \
  --execution-engine=jit \
  --guest-file=/boot.env="$PACK/boot.env" \
  --guest-file=/payload/usr/local/bin/run-benches.sh="$PACK/guest-run-benches.sh" \
  --guest-file=/payload/usr/local/share/cpu-benches/run-cpu-benches.sh="$PACK/run-cpu-benches.sh" \
  --guest-file=/payload/usr/local/share/cpu-benches/tiny-sha/Makefile="$PACK/tiny-sha/Makefile" \
  --guest-file=/payload/usr/local/share/cpu-benches/native-loop/loop.c="$PACK/native-loop/loop.c" \
  --guest-file=/payload/usr/local/share/cpu-benches/tiny-sha/main.c="$PACK/tiny-sha/main.c" \
  --guest-file=/payload/usr/local/share/cpu-benches/tiny-sha/sha256.c="$PACK/tiny-sha/sha256.c" \
  --guest-file=/payload/usr/local/share/cpu-benches/tiny-sha/sha256.h="$PACK/tiny-sha/sha256.h" \
  "${extra[@]}" \
  mem=2G ncpus=8 \
  ubd0c="$ROOTFS" \
  rootfstype=ext4
