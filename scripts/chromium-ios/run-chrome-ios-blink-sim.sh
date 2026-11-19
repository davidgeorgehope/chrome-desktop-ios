#!/bin/bash
# Launch the use_blink iOS Chrome app (//ios/chrome UI on Blink via
# ios/web/content) in an iPad Simulator so the regular-width UI shows the
# tab strip + omnibox. BrowserEngineKit extensions cannot start on adhoc
# Simulator signatures, so run Blink single-process with in-process GPU
# (needs patches/chromium-ios/0001). Desktop identity comes from 0002.
# NetTaskScheduler must be off: in single-process the iOS-side in-process
# NetworkService on the IO thread picks up the content network thread's
# net::TaskRunnerGlobals and trips SimpleWatcher's sequence DCHECK.
#
# Usage: run-chrome-ios-blink-sim.sh run [url] [tag] | shutdown | status
set -euo pipefail
OUT="${CHROMIUM_OUT:-$HOME/chromium-build/chromium/src/out/Release-iphonesimulator}"
APP="${CHROME_APP:-$OUT/Chromium.app}"
BUNDLE_ID="${CHROME_BUNDLE_ID:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")}"
UDID="${SIM_UDID:-booted}"   # iPad (A16)
WORKDIR="${WORKDIR:-$HOME/chromium-sim-run/chrome}"
log() { printf '%s %s\n' "$(date '+%F %T %Z')" "$*"; }

boot() {
  if xcrun simctl list devices booted | grep -q "$UDID"; then return 0; fi
  xcrun simctl list devices booted | grep -q Booted && xcrun simctl shutdown all || true
  xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID" -b
}

run() {
  local url="${1:-https://www.whatismybrowser.com/}" tag="${2:-chrome}"
  mkdir -p "$WORKDIR"
  local prefix="$WORKDIR/${tag}-$(date +%Y%m%d-%H%M%S)"
  # Fresh boot each run: queued "Open in Chromium?" URL contexts from earlier
  # runs trip DCHECK(!_sceneState.URLContextsToOpen) in scene_delegate.mm.
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  boot
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP" 2>&1 | tee "$prefix.install.txt"
  # Skip first-run UI so the browser opens straight to tabs.
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" FirstRunForceDisabled -bool YES || true
  xcrun simctl launch --terminate-running-process \
    --stdout="$prefix.stdout.txt" --stderr="$prefix.stderr.txt" \
    "$UDID" "$BUNDLE_ID" --single-process --in-process-gpu \
    --enable-logging=stderr \
    --disable-features=NetTaskScheduler,NetworkServiceTaskScheduler \
    ${EXTRA_ARGS:-} 2>&1 | tee "$prefix.launch.txt"
  python3 -c 'import time; time.sleep(8)'
  # Route through Chromium's own scheme so the sim's default browser (Safari)
  # never handles the URL: https://x -> chromiums://x, http://x -> chromium://x.
  if [[ -n "$url" ]]; then
    local curl="${url/#https:/chromiums:}"; curl="${curl/#http:/chromium:}"
    xcrun simctl openurl "$UDID" "$curl" || true
    # SpringBoard asks "Open in Chromium?"; confirm it (brew cameroncooke/axe/axe).
    /opt/homebrew/bin/axe tap --label Open --wait-timeout 10 --udid "$UDID" || true
  fi
  python3 -c 'import time; time.sleep(12)'
  xcrun simctl io "$UDID" screenshot "$prefix.png"
  log "SHOT $prefix.png"
}

case "${1:-}" in
  run) run "${2:-https://www.whatismybrowser.com/}" "${3:-chrome}" ;;
  shutdown) xcrun simctl shutdown "$UDID" || true ;;
  status) xcrun simctl list devices booted; echo "APP=$APP BUNDLE_ID=$BUNDLE_ID" ;;
  *) echo "usage: $0 run [url] [tag]|shutdown|status" >&2; exit 2 ;;
esac
