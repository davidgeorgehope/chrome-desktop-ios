#!/bin/bash
set -u
# Checkout + out/ live under ROOT. Override to use a different disk, e.g. the USB volume.
ROOT="${CHROMIUM_BUILD_ROOT:-$HOME/chromium-build}"
export PATH="$ROOT/depot_tools:$HOME/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"
FETCH_LOG=$ROOT/logs/fetch.log
BUILD_LOG=$ROOT/logs/build.log
mkdir -p "$ROOT/logs" "$ROOT/chromium"
# also mirror short status into /tmp
STATUS=/tmp/chromium-jobs.status
logf() { echo "$(date '+%Y-%m-%d %H:%M:%S %Z') $*" | tee -a "$FETCH_LOG" "$STATUS"; }
logb() { echo "$(date '+%Y-%m-%d %H:%M:%S %Z') $*" | tee -a "$BUILD_LOG" "$STATUS"; }
: > "$STATUS"
echo $$ > /tmp/chromium-fetch-build.pid
logf "FETCH_BUILD_WRAPPER_PID $$ ROOT=$ROOT"

# depot_tools
if [ ! -x "$ROOT/depot_tools/fetch" ]; then
  logf "CLONING_DEPOT_TOOLS"
  if ! git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$ROOT/depot_tools" >>"$FETCH_LOG" 2>&1; then
    logf "DEPOT_TOOLS_CLONE_FAILED"
    echo FAILED > /tmp/chromium-fetch.failed
    exit 1
  fi
fi
export PATH="$ROOT/depot_tools:$PATH"
# Avoid interactive prompts
export DEPOT_TOOLS_UPDATE=1
export DEPOT_TOOLS_METRICS=0

cd "$ROOT/chromium"
if [ "${RESUME_BUILD:-}" = 1 ] && [ -f .gclient ] && [ -d src ]; then
  logf "RESUME_BUILD skip fetch/gclient sync"
  echo FETCH_OK > /tmp/chromium-fetch.status
elif [ ! -f .gclient ]; then
  logf "START_FETCH --no-history ios"
  echo FETCH_RUNNING > /tmp/chromium-fetch.status
  if ! fetch --no-history ios >>"$FETCH_LOG" 2>&1; then
    logf "FETCH_FAILED"
    echo FAILED > /tmp/chromium-fetch.failed
    echo FAILED > /tmp/chromium-fetch.status
    exit 1
  fi
else
  logf "GCLIENT_ALREADY_PRESENT — running gclient sync --no-history"
  echo FETCH_RUNNING > /tmp/chromium-fetch.status
  if ! gclient sync --no-history >>"$FETCH_LOG" 2>&1; then
    logf "GCLIENT_SYNC_FAILED"
    echo FAILED > /tmp/chromium-fetch.failed
    echo FAILED > /tmp/chromium-fetch.status
    exit 1
  fi
fi

# Ensure target_os = ["ios"] in .gclient
if [ -f .gclient ] && ! grep -q 'target_os' .gclient; then
  printf '\ntarget_os = ["ios"]\n' >> .gclient
  logf "APPENDED_target_os"
fi
# Show target_os line only (no secrets)
grep -n 'target_os' .gclient | tee -a "$FETCH_LOG" "$STATUS" || true
logf "FETCH_OK"
echo FETCH_OK > /tmp/chromium-fetch.status
echo FETCH_OK > /tmp/chromium-fetch.ok

if [ ! -d "$ROOT/chromium/src" ]; then
  logf "NO_SRC_DIR"
  echo FAILED > /tmp/chromium-build.failed
  exit 1
fi

cd "$ROOT/chromium/src"
OUT=out/Release-iphonesimulator
ARGS=$(cat <<'EOF'
target_os = "ios"
target_environment = "simulator"
target_cpu = "arm64"
use_blink = true
is_debug = false
symbol_level = 1
blink_symbol_level = 0
v8_symbol_level = 0
ios_content_shell_bundle_identifier = "com.davidhope.deskbrowser.shell"
ios_chromium_bundle_id = "com.davidhope.deskbrowser.blink"
EOF
)
echo BUILD_RUNNING > /tmp/chromium-build.status
# FORCE_GN_GEN=1 regenerates ninja files after moving the checkout to a new path.
if [ "${FORCE_GN_GEN:-}" = 1 ]; then
  logb "FORCE_GN_GEN $OUT"
  if ! gn gen "$OUT" --args="$ARGS" >>"$BUILD_LOG" 2>&1; then
    logb "GN_GEN_FAILED"
    echo FAILED > /tmp/chromium-build.failed
    echo FAILED > /tmp/chromium-build.status
    exit 1
  fi
  logb "GN_GEN_OK"
elif [ "${RESUME_BUILD:-}" = 1 ] && [ -f "$OUT/build.ninja" ]; then
  logb "RESUME_BUILD skip gn gen (build.ninja present)"
else
  logb "START_GN_GEN $OUT"
  if ! gn gen "$OUT" --args="$ARGS" >>"$BUILD_LOG" 2>&1; then
    logb "GN_GEN_FAILED"
    echo FAILED > /tmp/chromium-build.failed
    echo FAILED > /tmp/chromium-build.status
    exit 1
  fi
  logb "GN_GEN_OK"
fi
# $! is unbound under set -u unless a background job was started.
# Record the wrapper PID; autoninja runs in the foreground.
echo $$ > /tmp/chromium-build.pid
logb "START_AUTONINJA content_shell"
if ! autoninja -C "$OUT" content_shell >>"$BUILD_LOG" 2>&1; then
  logb "BUILD_FAILED"
  echo FAILED > /tmp/chromium-build.failed
  echo FAILED > /tmp/chromium-build.status
  exit 1
fi
logb "BUILD_OK"
echo BUILD_OK > /tmp/chromium-build.status
echo BUILD_OK > /tmp/chromium-build.ok
