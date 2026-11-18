#!/bin/bash
# Incremental device Chrome rebuild with the built-in StikJIT helper,
# then sign to Chromium-device-autojit.ipa. Failure webhook is last
# ninja/gn/xcodebuild errors, not a leftover crash dump.
set -u
set -o pipefail
export TMPDIR=/tmp
export TMP=/tmp
ROOT="$HOME/chromium-build"
SRC="$ROOT/chromium/src"
OUT="$SRC/out/Release-iphoneos"
LOGDIR="$ROOT/logs"
JOB=chromium-ios-chrome-device-autojit
ST="$LOGDIR/chrome-device-autojit-build.status"
RUNLOG="$LOGDIR/chrome-device-autojit-build.current.log"
HIST="$LOGDIR/chrome-device-autojit-build.log"
DETAIL="/tmp/chrome-device-autojit-detail.txt"
export SIGNED_IPA="$OUT/Chromium-device-autojit.ipa"
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
    r"FAILED:|error:|fatal error|undefined (?:reference|symbol)|Build Failure|NINJA rc=|GN rc=|XCODEBUILD rc=|ERROR",
    ln)]
out = interesting[-30:] if interesting else lines[-30:]
open(dest, "w", encoding="utf-8").write("\n".join(out) + ("\n" if out else ""))
print("detail lines:", len(out))
PYE
}

AUTOJIT="${AUTOJIT_ROOT:-$ROOT/autojit}"
# Prefer the copy next to this script (repo), then the mini working copy.
HELPER_BUILD="$(cd "$(dirname "$0")" && pwd)/autojit/build-helper.sh"
[ -x "$HELPER_BUILD" ] || HELPER_BUILD="$AUTOJIT/build-helper.sh"

{
  echo "$(date '+%F %T %Z') START autojit incremental TMPDIR=/tmp"
  export PATH="$ROOT/depot_tools:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
  echo "$(date '+%F %T %Z') building JIT helper"
  "$HELPER_BUILD"
  echo "$(date '+%F %T %Z') HELPER rc=$?"
  cd "$SRC"
  gn gen "$OUT"
  echo "$(date '+%F %T %Z') GN rc=$?"
  autoninja -C "$OUT" -j "${JOBS:-8}" chrome
  echo "$(date '+%F %T %Z') NINJA rc=$?"
} 2>&1 | tee -a "$RUNLOG" "$HIST"

helper_rc=$(sed -n 's/.*HELPER rc=\([0-9][0-9]*\).*/\1/p' "$RUNLOG" | tail -1)
gn_rc=$(sed -n 's/.*GN rc=\([0-9][0-9]*\).*/\1/p' "$RUNLOG" | tail -1)
rc=$(sed -n 's/.*NINJA rc=\([0-9][0-9]*\).*/\1/p' "$RUNLOG" | tail -1)
if [ -z "${rc:-}" ]; then rc=1; fi
if [ -n "${helper_rc:-}" ] && [ "$helper_rc" -ne 0 ]; then rc=$helper_rc; fi
if [ -n "${gn_rc:-}" ] && [ "$gn_rc" -ne 0 ]; then rc=$gn_rc; fi
# autoninja/siso has been seen exiting 0 after "Build Failure" / "steps failed".
if grep -E 'Build Failure:|[0-9]+ steps failed:' "$RUNLOG" >/dev/null; then
  echo "$(date '+%F %T %Z') ninja log reports a failed step; overriding rc=1" | tee -a "$RUNLOG" "$HIST"
  rc=1
fi
OBJ="$OUT/obj/content/app/app/deskbrowser_builtin_jit.o"
SRC_MM="$SRC/content/app/ios/deskbrowser_builtin_jit.mm"
if [ ! -f "$OBJ" ] || [ "$SRC_MM" -nt "$OBJ" ]; then
  echo "$(date '+%F %T %Z') builtin JIT object missing or stale; overriding rc=1" | tee -a "$RUNLOG" "$HIST"
  rc=1
fi
APP_BIN="$OUT/Chromium.app/Chromium"
if [ -f "$APP_BIN" ] && [ -f "$OBJ" ] && [ "$OBJ" -nt "$APP_BIN" ]; then
  echo "$(date '+%F %T %Z') Chromium.app is older than the new JIT object; overriding rc=1" | tee -a "$RUNLOG" "$HIST"
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  echo "$(date '+%F %T %Z') signing $SIGNED_IPA" | tee -a "$RUNLOG" "$HIST"
  SIGNER="$ROOT/sign-chrome-ios-device-autojit.sh"
  [ -x "$SIGNER" ] || SIGNER="$(cd "$(dirname "$0")" && pwd)/sign-chrome-ios-device-autojit.sh"
  if "$SIGNER" 2>&1 | tee -a "$RUNLOG" "$HIST"; then
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
echo "$(date '+%F %T %Z') END BUILD_FAILED rc=$rc" | tee -a "$RUNLOG" "$HIST"
extract_errors
"$ROOT/notify-poke.sh" "$JOB" BUILD_FAILED "$rc" "$DETAIL" || true
exit "$rc"
