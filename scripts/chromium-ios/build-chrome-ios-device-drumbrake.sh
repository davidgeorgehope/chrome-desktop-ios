#!/bin/bash
# Incremental device Chrome rebuild with v8_enable_drumbrake, then sign
# with the explicit memory-entitlement profile to a versioned IPA.
# Failure webhook is last ninja/gn errors, not a leftover crash dump.
set -u
set -o pipefail
export TMPDIR=/tmp
export TMP=/tmp
ROOT="$HOME/chromium-build"
SRC="$ROOT/chromium/src"
OUT="$SRC/out/Release-iphoneos"
LOGDIR="$ROOT/logs"
JOB=chromium-ios-chrome-device-drumbrake
ST="$LOGDIR/chrome-device-drumbrake-build.status"
RUNLOG="$LOGDIR/chrome-device-drumbrake-build.current.log"
HIST="$LOGDIR/chrome-device-drumbrake-build.log"
DETAIL="/tmp/chrome-device-drumbrake-detail.txt"
export SIGNED_IPA="$OUT/Chromium-device-jit-mem-drumbrake.ipa"
mkdir -p "$LOGDIR"
echo RUNNING > "$ST"
: > "$RUNLOG"

extract_errors() {
  /usr/bin/python3 - "$RUNLOG" "$DETAIL" <<'PYE'
import re, sys
src, dest = sys.argv[1], sys.argv[2]
ansi = re.compile(r"\x1b\[[0-9;]*[mK]")
text = open(src, errors="replace").read()
lines = [ansi.sub("", ln).rstrip() for ln in text.splitlines()]
interesting = [ln for ln in lines if re.search(
    r"FAILED:|error:|fatal error:|undefined (?:reference|symbol)|Build Failure|NINJA rc=|GN rc=|ERROR",
    ln)]
out = interesting[-30:] if interesting else lines[-30:]
open(dest, "w", encoding="utf-8").write("\n".join(out) + ("\n" if out else ""))
print("detail lines:", len(out))
PYE
}

{
  echo "$(date '+%F %T %Z') START drumbrake incremental TMPDIR=/tmp"
  export PATH="$ROOT/depot_tools:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
  cd "$SRC"
  gn gen "$OUT"
  echo "$(date '+%F %T %Z') GN rc=$?"
  autoninja -C "$OUT" -j "${JOBS:-8}" chrome
  echo "$(date '+%F %T %Z') NINJA rc=$?"
} 2>&1 | tee -a "$RUNLOG" "$HIST"

gn_rc=$(tail -80 "$RUNLOG" | sed -n 's/.*GN rc=\([0-9][0-9]*\).*/\1/p' | tail -1)
rc=$(tail -80 "$RUNLOG" | sed -n 's/.*NINJA rc=\([0-9][0-9]*\).*/\1/p' | tail -1)
if [ -z "${gn_rc:-}" ]; then gn_rc=1; fi
if [ -z "${rc:-}" ]; then rc=1; fi
if [ "$gn_rc" -ne 0 ]; then rc=$gn_rc; fi

if [ "$rc" -eq 0 ]; then
  echo "$(date '+%F %T %Z') signing $SIGNED_IPA" | tee -a "$RUNLOG" "$HIST"
  if "$ROOT/sign-chrome-ios-device-mem.sh" 2>&1 | tee -a "$RUNLOG" "$HIST"; then
    echo done > "$ST"
    echo "$(date '+%F %T %Z') END done rc=0" | tee -a "$RUNLOG" "$HIST"
    tail -30 "$RUNLOG" | sed 's/\x1b\[[0-9;]*[mK]//g' > "$DETAIL"
    "$ROOT/notify-poke.sh" "$JOB" done 0 "$DETAIL" || true
    exit 0
  else
    echo SIGN_FAILED > "$ST"
    echo "$(date '+%F %T %Z') END SIGN_FAILED" | tee -a "$RUNLOG" "$HIST"
    extract_errors
    "$ROOT/notify-poke.sh" "$JOB" SIGN_FAILED 2 "$DETAIL" || true
    exit 2
  fi
fi

echo BUILD_FAILED > "$ST"
echo "$(date '+%F %T %Z') END BUILD_FAILED rc=$rc gn_rc=$gn_rc" | tee -a "$RUNLOG" "$HIST"
extract_errors
"$ROOT/notify-poke.sh" "$JOB" BUILD_FAILED "$rc" "$DETAIL" || true
exit "$rc"
