#!/bin/bash
# Builds the iOS Chrome-on-Blink app for a real arm64 iPhone (unsigned),
# then signs it and packs an IPA (sign-chrome-ios-device.sh). Meant to run
# from a one-shot LaunchAgent in the GUI session so codesign can reach the
# login keychain identity without the security CLI. Reports its own finish or
# failure through notify-poke.sh (optional webhook). Resume-safe.
#
# out/Release-iphoneos/args.gn: see chrome-ios-device.args.gn next to this file.
set -u
ROOT="$HOME/chromium-build"
export PATH="$ROOT/depot_tools:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
cd "$ROOT/chromium/src"
OUT=${CHROMIUM_OUT:-out/Release-iphoneos}
LOG=$ROOT/logs/chrome-device-build.log
ST=$ROOT/logs/chrome-device-build.status
DETAIL=/tmp/chrome-device-build-detail.txt
J=${JOBS:-8}
JOB=chromium-ios-chrome-device
mkdir -p "$ROOT/logs"
echo RUNNING > "$ST"
echo "$(date "+%F %T %Z") START chrome device -j$J" >> "$LOG"
finish() {  # <status> <rc>
  echo "$1" > "$ST"
  echo "$(date "+%F %T %Z") END $1 rc=$2" >> "$LOG"
  { grep -E "FAILED|error:" "$LOG" | tail -15; tail -8 "$LOG"; } > "$DETAIL"
  "$ROOT/notify-poke.sh" "$JOB" "$1" "$2" "$DETAIL"
  # One-shot LaunchAgent: remove its plist so it never reruns at login.
  rm -f "$HOME/Library/LaunchAgents/com.davidhope.chrome-ios-device-build.plist"
  exit "$2"
}
[ -f "$OUT/build.ninja" ] || gn gen "$OUT" >> "$LOG" 2>&1 || finish GN_FAILED 1
autoninja -C "$OUT" -j "$J" chrome >> "$LOG" 2>&1 || finish BUILD_FAILED 1
echo "$(date "+%F %T %Z") BUILD_OK; signing" >> "$LOG"
"$ROOT/sign-chrome-ios-device.sh" >> "$LOG" 2>&1 || finish SIGN_FAILED 2
finish done 0
