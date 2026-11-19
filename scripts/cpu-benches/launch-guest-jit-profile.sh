#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export LANG=C

BENCH="${1:-sh_loop}"
case "$BENCH" in
  sh_loop|compile) ;;
  *) echo "usage: $0 sh_loop|compile" >&2; exit 2 ;;
esac

ROOT=$HOME/linux-ios-bakeoff/src/Kernarium
BIN="$ROOT/.build/presets/macos-integration/bin/uml-darwin"
NOTES=$HOME/linux-ios-bakeoff/notes
PACK="$NOTES/cpu-benches"
LOGDIR="$NOTES/jit-baseline"
ROOTFS=/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-minimal.ext4
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$LOGDIR/guest-jit-profile-${BENCH}-${STAMP}.log"
PROFILE_FILE="${UML_JIT_PROFILE_FILE:-/tmp/uml-jit-profile-${BENCH}.txt}"
CONTROL_FILE="${UML_JIT_PROFILE_CONTROL:-/tmp/uml-jit-profile.ctl}"

[ -x "$BIN" ] || { echo "missing uml-darwin"; exit 1; }
[ -f "$ROOTFS" ] || { echo "missing rootfs"; exit 1; }
mkdir -p "$LOGDIR" "$PACK"

printf 'CPU_BENCH_ONLY=%s\nexport CPU_BENCH_ONLY\n' "$BENCH" > "$PACK/profile.env"
rm -f "$PROFILE_FILE" "$CONTROL_FILE"

# Watch the serial log and reset host counters after apk, before compile.
touch "$LOG"
(
  tail -n 0 -F "$LOG" 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      *UML_JIT_PROFILE_RESET*)
        printf 'reset\n' > "$CONTROL_FILE"
        echo "PROFILE_WATCHER reset at $(date)" >> "$LOGDIR/profile-watcher.log"
        ;;
      *UML_JIT_PROFILE_DUMP*)
        printf 'dump\n' > "$CONTROL_FILE"
        # The flusher polls every 100ms; wait for the file to be rewritten.
        sleep 0.3
        if [ -f "$PROFILE_FILE" ]; then
          cp -f "$PROFILE_FILE" "${PROFILE_FILE%.txt}-snapshot.txt"
          echo "PROFILE_WATCHER dump at $(date) snapshot=${PROFILE_FILE%.txt}-snapshot.txt" >> "$LOGDIR/profile-watcher.log"
        else
          echo "PROFILE_WATCHER dump at $(date) (no file yet)" >> "$LOGDIR/profile-watcher.log"
        fi
        ;;
      *GUEST_PROFILE_DONE*)
        printf 'dump\n' > "$CONTROL_FILE"
        echo "PROFILE_WATCHER done at $(date)" >> "$LOGDIR/profile-watcher.log"
        ;;
    esac
  done
) &
WATCHER=$!
trap 'kill $WATCHER 2>/dev/null || true' EXIT

export UML_JIT_PROFILE=1
export UML_JIT_PROFILE_FILE="$PROFILE_FILE"
export UML_JIT_PROFILE_CONTROL="$CONTROL_FILE"

echo "LAUNCH $(date) jit profile bench=$BENCH file=$PROFILE_FILE"

extra=()
if [ -f "$PACK/apks.tar" ]; then
  extra+=(--guest-file=/payload/usr/local/share/cpu-benches/apks.tar="$PACK/apks.tar")
fi

# script(1) keeps serial markers line-buffered on a pty.
script -q -F "$LOG" "$BIN" \
  --execution-engine=jit \
  --guest-file=/boot.env="$PACK/boot.env" \
  --guest-file=/payload/usr/local/bin/run-benches.sh="$PACK/guest-run-profile.sh" \
  --guest-file=/payload/usr/local/share/cpu-benches/run-cpu-benches.sh="$PACK/run-cpu-benches.sh" \
  --guest-file=/payload/usr/local/share/cpu-benches/profile.env="$PACK/profile.env" \
  --guest-file=/payload/usr/local/share/cpu-benches/tiny-sha/Makefile="$PACK/tiny-sha/Makefile" \
  --guest-file=/payload/usr/local/share/cpu-benches/native-loop/loop.c="$PACK/native-loop/loop.c" \
  --guest-file=/payload/usr/local/share/cpu-benches/tiny-sha/main.c="$PACK/tiny-sha/main.c" \
  --guest-file=/payload/usr/local/share/cpu-benches/tiny-sha/sha256.c="$PACK/tiny-sha/sha256.c" \
  --guest-file=/payload/usr/local/share/cpu-benches/tiny-sha/sha256.h="$PACK/tiny-sha/sha256.h" \
  "${extra[@]}" \
  mem=2G ncpus=8 \
  ubd0c="$ROOTFS" \
  rootfstype=ext4

echo "PROFILE_FILE $PROFILE_FILE"
if [ -f "$PROFILE_FILE" ]; then
  echo "======= $PROFILE_FILE ======="
  cat "$PROFILE_FILE"
fi
echo "LOG $LOG"
