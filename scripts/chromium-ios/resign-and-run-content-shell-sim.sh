#!/bin/bash
# Re-sign iOS Simulator content_shell with BrowserEngineKit entitlements and
# launch it in a booted simulator. Chromium's codesign.py only passes
# --entitlements for non-simulator platforms, so the Release-iphonesimulator
# bundle is adhoc-signed with an empty entitlement set. Without
# com.apple.developer.web-browser-engine.host (and the matching appex
# entitlements) BrowserEngineKit cannot start the renderer / GPU / network
# extension processes, which shows up as a Chrome-shell toolbar over a solid
# gray content area.
#
# Usage:
#   resign-and-run-content-shell-sim.sh resign
#   resign-and-run-content-shell-sim.sh boot
#   resign-and-run-content-shell-sim.sh run [url] [tag]
#   resign-and-run-content-shell-sim.sh shutdown
#   resign-and-run-content-shell-sim.sh status
set -euo pipefail

OUT="${CHROMIUM_OUT:-$HOME/chromium-build/chromium/src/out/Release-iphonesimulator}"
APP="${CONTENT_SHELL_APP:-$OUT/content_shell.app}"
XC="$OUT/obj/content/shell"
BUNDLE_ID="${CONTENT_SHELL_BUNDLE_ID:-com.davidhope.deskbrowser.shell}"
UDID="${SIM_UDID:-1D5BB940-9803-4BFB-A283-3FFD14BD2D2F}"
WORKDIR="${WORKDIR:-$HOME/chromium-sim-run}"
DESKTOP_UA="${DESKTOP_UA:-Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/160.0.0.0 Safari/537.36}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*"; }

need_app() {
  if [[ ! -d "$APP" ]]; then
    log "MISSING_APP $APP"
    exit 1
  fi
}

resign() {
  need_app
  local missing=0
  local name
  for name in content_shell content_process gpu_process network_process; do
    if [[ ! -f "$XC/$name.xcent" ]]; then
      log "MISSING_XCENT $XC/$name.xcent"
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi

  log "RESIGN_START $APP"
  # Inside-out: frameworks, then appexes, then the app.
  if [[ -d "$APP/Frameworks/TestTraceProcessor.framework" ]]; then
    codesign --force --sign - --timestamp=none \
      "$APP/Frameworks/TestTraceProcessor.framework"
  fi
  if [[ -d "$APP/Frameworks/content_shell_framework.framework" ]]; then
    codesign --force --sign - --timestamp=none \
      "$APP/Frameworks/content_shell_framework.framework"
  fi
  codesign --force --sign - --timestamp=none \
    --entitlements "$XC/content_process.xcent" \
    "$APP/Extensions/content_process.appex"
  codesign --force --sign - --timestamp=none \
    --entitlements "$XC/gpu_process.xcent" \
    "$APP/Extensions/gpu_process.appex"
  codesign --force --sign - --timestamp=none \
    --entitlements "$XC/network_process.xcent" \
    "$APP/Extensions/network_process.appex"
  codesign --force --sign - --timestamp=none \
    --entitlements "$XC/content_shell.xcent" \
    "$APP"

  log "RESIGN_VERIFY"
  codesign -dv --entitlements - "$APP" 2>&1 | sed -n '1,80p'
  echo "======= CONTENT PROCESS ENTITLEMENTS ======="
  codesign -d --entitlements - "$APP/Extensions/content_process.appex" 2>&1
  echo "======= GPU PROCESS ENTITLEMENTS ======="
  codesign -d --entitlements - "$APP/Extensions/gpu_process.appex" 2>&1
  echo "======= NETWORK PROCESS ENTITLEMENTS ======="
  codesign -d --entitlements - "$APP/Extensions/network_process.appex" 2>&1
  log "RESIGN_DONE"
}

boot() {
  mkdir -p "$WORKDIR"
  local state
  state="$(xcrun simctl list devices | awk -v u="$UDID" '$0 ~ u {print}')"
  log "SIM_TARGET $state"
  if xcrun simctl list devices booted | grep -q "$UDID"; then
    log "SIM_ALREADY_BOOTED $UDID"
    return 0
  fi
  # Shut down any other booted sim to keep memory down.
  if xcrun simctl list devices booted | grep -q Booted; then
    log "SHUTTING_OTHER_SIMS"
    xcrun simctl shutdown all || true
  fi
  log "BOOT_START $UDID"
  xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b
  log "BOOT_DONE $UDID"
}

shutdown_sim() {
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  if [[ -f "$WORKDIR/logstream.pid" ]]; then
    kill "$(cat "$WORKDIR/logstream.pid")" 2>/dev/null || true
    rm -f "$WORKDIR/logstream.pid"
  fi
  log "SHUTDOWN_START"
  xcrun simctl shutdown "$UDID" || xcrun simctl shutdown all || true
  log "SHUTDOWN_DONE"
}

status() {
  echo "APP=$APP"
  echo "UDID=$UDID"
  xcrun simctl list devices booted || true
  echo "======= MEMORY ======="
  memory_pressure | head -16 || true
  echo "======= SIGNATURE ======="
  codesign -d --entitlements - "$APP" 2>&1 | tail -20 || true
}

run() {
  need_app
  local url="${1:-https://example.com/}"
  local tag="${2:-example}"
  mkdir -p "$WORKDIR/shots"
  local stamp
  stamp="$(date '+%Y%m%d-%H%M%S')"
  local prefix="$WORKDIR/${tag}-${stamp}"

  if ! xcrun simctl list devices booted | grep -q "$UDID"; then
    boot
  fi

  xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true

  log "INSTALL_START"
  local install_out
  set +e
  install_out="$(xcrun simctl install booted "$APP" 2>&1)"
  local install_rc=$?
  set -e
  printf '%s\n' "$install_out" | tee "${prefix}.install.txt"
  log "INSTALL_RC=$install_rc"

  # Fresh unified log stream for this launch.
  if [[ -f "$WORKDIR/logstream.pid" ]]; then
    kill "$(cat "$WORKDIR/logstream.pid")" 2>/dev/null || true
    rm -f "$WORKDIR/logstream.pid"
  fi
  # Keep the predicate broad enough to catch BEK / extension install failures
  # without dumping the entire system log.
  xcrun simctl spawn booted log stream --level debug --style compact \
    --predicate '(process CONTAINS[c] "content_shell") OR (process CONTAINS[c] "content_process") OR (process CONTAINS[c] "gpu_process") OR (process CONTAINS[c] "network_process") OR (subsystem CONTAINS[c] "BrowserEngine") OR (eventMessage CONTAINS[c] "BrowserEngine") OR (eventMessage CONTAINS[c] "BEWebContent") OR (eventMessage CONTAINS[c] "BERendering") OR (eventMessage CONTAINS[c] "BENetworking") OR (eventMessage CONTAINS[c] "web-browser-engine") OR (eventMessage CONTAINS[c] "Authorization is required") OR (eventMessage CONTAINS[c] "Install Failed") OR (composedMessage CONTAINS[c] "content_shell")' \
    >"${prefix}.logstream.txt" 2>"${prefix}.logstream.err" &
  echo $! > "$WORKDIR/logstream.pid"
  log "LOGSTREAM_PID $(cat "$WORKDIR/logstream.pid")"

  local launch_args=(
    --enable-logging=stderr
    --v=1
    --single-process
    --in-process-gpu
    --user-agent="$DESKTOP_UA"
    "$url"
  )
  log "LAUNCH_START tag=$tag url=$url ua=$DESKTOP_UA"
  local t0 t1 elapsed pid=""
  t0="$(python3 -c 'import time; print(time.time())')"
  set +e
  xcrun simctl launch --terminate-running-process \
    --stdout="${prefix}.stdout.txt" \
    --stderr="${prefix}.stderr.txt" \
    booted "$BUNDLE_ID" \
    "${launch_args[@]}" \
    >"${prefix}.launch.txt" 2>&1
  local launch_rc=$?
  set -e
  t1="$(python3 -c 'import time; print(time.time())')"
  elapsed="$(python3 -c "print(f'{$t1 - $t0:.3f}')")"
  pid="$(awk -F': ' '/^'"$BUNDLE_ID"':/{print $2; exit}' "${prefix}.launch.txt" | tr -d '[:space:]')"
  log "LAUNCH_RC=$launch_rc launch_s=$elapsed pid=${pid:-none}"
  cat "${prefix}.launch.txt"

  # Poll for first non-empty screenshot and whether the process stays up.
  # 0.5s ticks, 20s budget; no long blocking sleep.
  local i running="unknown" first_shot=""
  local load_s=""
  for i in $(seq 1 40); do
    python3 -c 'import time; time.sleep(0.5)'
    if xcrun simctl spawn booted launchctl print "gui/$(xcrun simctl get_app_container booted "$BUNDLE_ID" 2>/dev/null | sed -n "s/.*\/Containers\/Data\/Application\/\([^/]*\).*/\1/p")" >/dev/null 2>&1; then
      :
    fi
    if [[ -n "$pid" ]] && xcrun simctl spawn booted ps -p "$pid" >/dev/null 2>&1; then
      running="true"
    else
      # Fallback: look for the executable name in the guest.
      if xcrun simctl spawn booted ps -axo pid,comm 2>/dev/null | grep -q 'content_shell$'; then
        running="true"
      else
        running="false"
      fi
    fi
    if (( i == 6 || i == 16 || i == 30 || i == 40 )); then
      local shot="$WORKDIR/shots/${tag}-${stamp}-${i}.png"
      xcrun simctl io booted screenshot "$shot" >/dev/null 2>&1 || true
      if [[ -z "$first_shot" && -f "$shot" ]]; then
        first_shot="$shot"
      fi
      log "SHOT i=$i running=$running $shot"
    fi
    if [[ "$running" == "false" && i -ge 6 ]]; then
      log "PROCESS_EXITED i=$i"
      break
    fi
  done
  load_s="$(python3 -c "print(f'{($i * 0.5):.1f}')")"

  # Final screenshot and process list.
  xcrun simctl io booted screenshot "$WORKDIR/shots/${tag}-${stamp}-final.png" >/dev/null 2>&1 || true
  xcrun simctl spawn booted ps -axo pid,rss,comm 2>/dev/null | tee "${prefix}.ps.txt" | grep -iE 'content_|gpu_process|network_process|BrowserEngine' || true

  if [[ -f "$WORKDIR/logstream.pid" ]]; then
    kill "$(cat "$WORKDIR/logstream.pid")" 2>/dev/null || true
    rm -f "$WORKDIR/logstream.pid"
  fi

  # Recent diagnostic reports (host-side, written if a sim process crashes).
  ls -lt "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | head -20 > "${prefix}.crashes.txt" || true

  python3 - <<PY
import json, time
from pathlib import Path
p = Path("${prefix}.report.json")
p.write_text(json.dumps({
    "tag": "$tag",
    "url": "$url",
    "ua": "$DESKTOP_UA",
    "launch_s": float("$elapsed"),
    "poll_s": float("$load_s"),
    "pid": "$pid",
    "running": "$running",
    "launch_rc": int("$launch_rc"),
    "install_rc": int("$install_rc"),
    "install_out": """$(python3 -c 'import pathlib,sys; print(pathlib.Path("'"${prefix}.install.txt"'").read_text()[:2000])')""",
    "launch_out": """$(python3 -c 'import pathlib; print(pathlib.Path("'"${prefix}.launch.txt"'").read_text()[:2000])')""",
    "ts": time.strftime("%Y-%m-%d %H:%M:%S %Z"),
    "prefix": "$prefix",
}, indent=2))
print(p.read_text())
PY
  log "RUN_DONE prefix=$prefix running=$running"
}

cmd="${1:-}"
shift || true
case "$cmd" in
  resign) resign ;;
  boot) boot ;;
  run) run "${1:-https://example.com/}" "${2:-example}" ;;
  shutdown) shutdown_sim ;;
  status) status ;;
  *)
    echo "usage: $0 resign|boot|run|shutdown|status" >&2
    exit 2
    ;;
esac
