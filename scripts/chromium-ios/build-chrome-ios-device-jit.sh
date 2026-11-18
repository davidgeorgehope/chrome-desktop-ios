#!/bin/bash
# Incremental device Chrome build + sign. Resume-safe. Failure webhook
# payload is the last ninja errors, not a leftover crash dump.
set -u
set -o pipefail
export TMPDIR=/tmp
export TMP=/tmp
ROOT="$HOME/chromium-build"
SRC="$ROOT/chromium/src"
OUT="$SRC/out/Release-iphoneos"
LOGDIR="$ROOT/logs"
JOB=chromium-ios-chrome-device-jit
ST="$LOGDIR/chrome-device-jit-build.status"
RUNLOG="$LOGDIR/chrome-device-jit-build.current.log"
HIST="$LOGDIR/chrome-device-jit-build.log"
DETAIL="/tmp/chrome-device-jit-detail.txt"
mkdir -p "$LOGDIR"
echo RUNNING > "$ST"
: > "$RUNLOG"

extract_errors() {
  /usr/bin/python3 - "$RUNLOG" "$DETAIL" <<'PY'
import re, sys
src, dest = sys.argv[1], sys.argv[2]
ansi = re.compile(r"\x1b\[[0-9;]*[mK]")
text = open(src, errors="replace").read()
lines = [ansi.sub("", ln).rstrip() for ln in text.splitlines()]
interesting = [ln for ln in lines if re.search(
    r"FAILED:|error:|fatal error:|undefined (?:reference|symbol)|Build Failure|NINJA rc=",
    ln)]
out = interesting[-30:] if interesting else lines[-30:]
open(dest, "w", encoding="utf-8").write("\n".join(out) + ("\n" if out else ""))
print("detail lines:", len(out))
PY
}

{
  echo "$(date '+%F %T %Z') START jit incremental TMPDIR=/tmp"
  export PATH="$ROOT/depot_tools:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
  cd "$SRC"
  autoninja -C "$OUT" -j "${JOBS:-8}" chrome
  echo "$(date '+%F %T %Z') NINJA rc=$?"
} 2>&1 | tee -a "$RUNLOG" "$HIST"
# The echo after autoninja succeeds, so read the rc the block printed.
rc=$(tail -20 "$RUNLOG" | sed -n 's/.*NINJA rc=\([0-9][0-9]*\).*/\1/p' | tail -1)
if [ -z "${rc:-}" ]; then
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  echo "$(date '+%F %T %Z') signing" | tee -a "$RUNLOG" "$HIST"
  if "$ROOT/sign-chrome-ios-device.sh" 2>&1 | tee -a "$RUNLOG" "$HIST"; then
    echo done > "$ST"
    echo "$(date '+%F %T %Z') END done rc=0" | tee -a "$RUNLOG" "$HIST"
    tail -20 "$RUNLOG" | sed 's/\x1b\[[0-9;]*[mK]//g' > "$DETAIL"
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
echo "$(date '+%F %T %Z') END BUILD_FAILED rc=$rc" | tee -a "$RUNLOG" "$HIST"
extract_errors
"$ROOT/notify-poke.sh" "$JOB" BUILD_FAILED "$rc" "$DETAIL" || true
exit "$rc"
