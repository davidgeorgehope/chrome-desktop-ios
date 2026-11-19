#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
UDID=${SIM_UDID:-booted}
BUNDLE=com.imxieyi.Kernarium
ROOT=$HOME/linux-ios-bakeoff
LOG=$ROOT/notes/kernarium-benches.log
exec > >(tee "$LOG") 2>&1
echo "==== CAPTURE START $(date) ===="

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
sleep 1

# Ensure the app still points at the patched image
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
mkdir -p "$CONTAINER/Documents" "$CONTAINER/tmp"
rm -f "$CONTAINER/tmp/kernarium-overlay.ext4"
ln -sfn /Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-minimal.ext4 \
  "$CONTAINER/Documents/alpine-3.24.2-minimal.ext4"

# Capture console until BENCH_DONE or timeout
export SIMCTL_CHILD_KERNARIUM_ROOTFS=alpine-3.24.2-minimal.ext4
# unbuffered-ish: use stdbuf if present; otherwise python later
set +e
xcrun simctl launch --console-pty "$UDID" "$BUNDLE" > "$ROOT/notes/kernarium-sim-launch-4.log" 2>&1 &
LPID=$!
echo "LAUNCH_PID=$LPID"

# Wait for BENCH_DONE up to 4 minutes
DEADLINE=$((SECONDS + 240))
FOUND=0
while (( SECONDS < DEADLINE )); do
  if grep -q "===BENCH_DONE===" "$ROOT/notes/kernarium-sim-launch-4.log" 2>/dev/null; then
    FOUND=1
    break
  fi
  sleep 2
done

echo "---- screenshot ----"
xcrun simctl io "$UDID" screenshot "$ROOT/screenshots/kernarium-05-benches.png" || true
date
if [[ $FOUND -eq 1 ]]; then
  echo "BENCH_DONE_SEEN $(date)"
else
  echo "BENCH_TIMEOUT $(date)"
fi

echo "======= CONSOLE (filtered benches) ======="
# extract from BENCH_START to end
if grep -q "===BENCH_START===" "$ROOT/notes/kernarium-sim-launch-4.log"; then
  awk 'p||/===BENCH_START===/{p=1} p' "$ROOT/notes/kernarium-sim-launch-4.log"
else
  echo "(no BENCH_START yet; tail follows)"
  tail -n 200 "$ROOT/notes/kernarium-sim-launch-4.log"
fi
echo "======= CAPTURE_OK $(date) found=$FOUND ======="
# leave the app running for more screenshots
