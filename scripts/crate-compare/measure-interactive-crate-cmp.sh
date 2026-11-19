#!/bin/bash
# Measure desktop interactivity on uml-darwin: app launch, scroll fps,
# and input latency (event-to-next-rAF once a real key or click arrives).
#
# Usage: measure-interactive.sh TAG BIN_PATH [firefox|chromium]
#
# Overlay: the labwc start script opts in when /usr/local/etc/interactive-metrics
# is injected, points the browser at http://127.0.0.1:8765/, and the page
# posts ===INTERACTIVE_*=== markers to the serial. Optional VNC injection
# after ===INTERACTIVE_READY_FOR_INPUT=== if vncdotool is on PATH
# (UML_VNC_DISPLAY, default 127.0.0.1:5900).
#
# This does not replace TTP (example.com). Run launch-ab-uml-darwin.sh
# plus score-ttp-shots.py for time-to-page.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export LANG=C
TAG="${1:?tag}"
BIN="${2:?bin}"; [ "$BIN" = - ] && BIN="$KBIN"
BROWSER="${3:-firefox}"
NOTES=$HOME/linux-ios-bakeoff/notes/macos-metal-desktop
FAST=$HOME/linux-ios-bakeoff/notes/desktop-guest-fast
HERE=$(cd "$(dirname "$0")/.." && pwd)
# Prefer the repo copy of the guest pack, then the mini bakeoff overlay.
GUEST_PACK="$HERE/desktop-guest"
if [ ! -f "$GUEST_PACK/start-desktop-labwc.sh" ] && [ -f "$FAST/start-desktop-labwc-persist.sh" ]; then
  GUEST_PACK="$FAST"
fi
METRICS_ROOT="$(cd "$(dirname "$0")/../desktop-guest/interactive-metrics" && pwd)"
START="$GUEST_PACK/start-desktop-labwc.sh"
if [ -f "$FAST/start-desktop-labwc-persist.sh" ]; then
  START="$FAST/start-desktop-labwc-persist.sh"
fi
# If the persist wrapper is the bakeoff one, still inject the repo start
# script as start-desktop.sh when we can (D4iPad baked images aside).
REPO_START="$HERE/desktop-guest/start-desktop-labwc.sh"
DEFAULT_LABWC=/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-desktop-labwc.ext4
CHROMIUM_LABWC=/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-desktop-labwc-chromium-20261113.ext4
if [ "$BROWSER" = chromium ] && [ -f "$CHROMIUM_LABWC" ]; then
  SOURCE=$CHROMIUM_LABWC
else
  SOURCE=$DEFAULT_LABWC
fi
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$NOTES/session-interactive-$TAG-$STAMP.log"
MEMLOG="$NOTES/persist-memory-interactive-$TAG-$STAMP.log"
mkdir -p "$NOTES"

if [ ! -x "$BIN" ] || [ ! -f "$SOURCE" ]; then
  echo "missing bin or rootfs: BIN=$BIN SOURCE=$SOURCE" >&2
  exit 1
fi

export UML_PREFLIGHT_GUEST_MEM=4G
if [ -f "$NOTES/preflight-uml-darwin.sh" ]; then
  # shellcheck disable=SC1091
  . "$NOTES/preflight-uml-darwin.sh"
elif [ -f "$HERE/macos-metal/preflight-uml-darwin.sh" ]; then
  # shellcheck disable=SC1091
  . "$HERE/macos-metal/preflight-uml-darwin.sh"
fi

export UML_GPU_DISPLAY=native
export UML_DESKTOP=labwc
unset UML_JIT_PERSISTENT_CACHE UML_JIT_PERSISTENT_CACHE_SOURCE
unset KERNARIUM_JIT_PERSISTENT_CACHE KERNARIUM_JIT_PERSISTENT_CACHE_SOURCE
export UML_JIT_CACHE_BUDGET="${UML_JIT_CACHE_BUDGET:-8G}"

FLAG=$(mktemp)
echo 1 > "$FLAG"
BOOTENV="$NOTES/boot.env"
READY="$FAST/desktop-ready.sh"
BWRAP="$FAST/bwrap-passthrough.sh"
FFPROF="$FAST/firefox-kernarium-profile.sh"
if [ -x "$HERE/desktop-guest/firefox-kernarium-profile.sh" ]; then
  FFPROF="$HERE/desktop-guest/firefox-kernarium-profile.sh"
fi

{
  echo "LAUNCH $(date) tag=$TAG bin=$BIN budget=${UML_JIT_CACHE_BUDGET} persist=off browser=$BROWSER interactive=1"
  echo "source=$SOURCE"
  ls -li "$BIN"
} | tee -a "$LOG"

(
  echo "memory sampler $TAG $(date) start_swap=${UML_SWAP_USED_AT_START:-0}M" >"$MEMLOG"
  for i in $(seq 1 80); do
    date >>"$MEMLOG"
    swline=$(sysctl vm.swapusage)
    echo "$swline" >>"$MEMLOG"
    ps -axo rss,pid,comm | awk 'tolower($3)~/(uml-darwin)/ {print}' >>"$MEMLOG"
    echo "-----" >>"$MEMLOG"
    if [ "${UML_ALLOW_HEAVY:-0}" != 1 ]; then
      used=$(echo "$swline" | sed -n 's/.*used = \([0-9.][0-9.]*\)M.*/\1/p')
      used=${used:-0}
      start=${UML_SWAP_USED_AT_START:-0}
      awk -v u="$used" -v s="$start" 'BEGIN { exit (u+0 > s+0 + 2048) }' || {
        echo "SWAP_ABORT used=${used}M start=${start}M limit=+2048M $(date)" | tee -a "$MEMLOG"
        /usr/bin/pgrep -f '[u]ml-darwin' | while read -r pid; do
          comm=$(ps -p "$pid" -o comm= 2>/dev/null || true)
          case "$comm" in *uml-darwin*) kill -TERM "$pid" 2>/dev/null || true ;; esac
        done
        break
      }
    fi
    sleep 2
  done
) &
MEMPID=$!

args=(
  --execution-engine=jit
  --gpu-display=native
  --gpu-width=1920
  --gpu-height=1080
  --gpu-auto-resize=off
  --guest-file=/boot.env="$BOOTENV"
  --guest-file=/payload/usr/local/etc/interactive-metrics="$FLAG"
  --guest-file=/payload/usr/local/bin/interactive-metrics-start.sh="$HERE/desktop-guest/interactive-metrics-start.sh"
  --guest-file=/payload/usr/local/share/interactive-metrics/index.html="$METRICS_ROOT/index.html"
  --guest-file=/payload/usr/local/share/interactive-metrics/warm.html="$METRICS_ROOT/warm.html"
  --guest-file=/payload/usr/local/share/interactive-metrics/cgi-bin/report="$METRICS_ROOT/cgi-bin/report"
  --guest-file=/payload/usr/local/share/interactive-metrics/metrics-httpd="$METRICS_ROOT/metrics-httpd"
  --guest-file=/payload/usr/local/share/interactive-metrics/evdev-poke.sh="$METRICS_ROOT/evdev-poke.sh"
  mem=${GUEST_MEM:-4G}
  ncpus=${NCPUS:-8}
  ubd0c="$SOURCE"
  rootfstype=ext4
)
if [ -x "$REPO_START" ]; then
  args+=( --guest-file=/payload/usr/local/bin/start-desktop.sh="$REPO_START" )
elif [ -x "$START" ]; then
  args+=( --guest-file=/payload/usr/local/bin/start-desktop.sh="$START" )
fi
if [ -x "$READY" ]; then
  args+=( --guest-file=/payload/usr/local/bin/desktop-ready.sh="$READY" )
fi
if [ -x "$BWRAP" ]; then
  args+=( --guest-file=/payload/usr/local/bin/bwrap-passthrough.sh="$BWRAP" )
fi
if [ -x "$FFPROF" ]; then
  args+=( --guest-file=/payload/usr/local/bin/firefox-kernarium-profile.sh="$FFPROF" )
fi
BROWSER_FILE=$(mktemp)
printf '%s\n' "$BROWSER" > "$BROWSER_FILE"
args+=( --guest-file=/payload/usr/local/etc/desktop-browser="$BROWSER_FILE" )
if [ -n "${UML_INTERACTIVE_INPUT_TIMEOUT_MS:-}" ]; then
  TIMEOUT_FILE=$(mktemp)
  printf '%s\n' "$UML_INTERACTIVE_INPUT_TIMEOUT_MS" > "$TIMEOUT_FILE"
  args+=( --guest-file=/payload/usr/local/etc/interactive-input-timeout-ms="$TIMEOUT_FILE" )
  echo "input_timeout_ms=$UML_INTERACTIVE_INPUT_TIMEOUT_MS"
fi
CHROMIUM_FLAGS_SRC=""
if [ -n "${UML_CHROMIUM_FLAGS:-}" ]; then
  CHROMIUM_FLAGS_SRC=$(mktemp)
  printf '%s
' $UML_CHROMIUM_FLAGS > "$CHROMIUM_FLAGS_SRC"
  echo "chromium-flags from UML_CHROMIUM_FLAGS=$UML_CHROMIUM_FLAGS"
elif [ -f "${UML_CHROMIUM_FLAGS_FILE:-}" ]; then
  CHROMIUM_FLAGS_SRC=$UML_CHROMIUM_FLAGS_FILE
  echo "chromium-flags from $CHROMIUM_FLAGS_SRC"
elif [ -f "$HERE/desktop-guest/chromium-flags" ]; then
  CHROMIUM_FLAGS_SRC="$HERE/desktop-guest/chromium-flags"
elif [ -f "$FAST/chromium-flags" ]; then
  CHROMIUM_FLAGS_SRC="$FAST/chromium-flags"
fi
if [ -n "$CHROMIUM_FLAGS_SRC" ]; then
  args+=( --guest-file=/payload/usr/local/etc/chromium-flags="$CHROMIUM_FLAGS_SRC" )
  echo "chromium-flags=$(tr '\n' ' ' < "$CHROMIUM_FLAGS_SRC")"
fi
args+=( --jit-cache-budget="${UML_JIT_CACHE_BUDGET}" )

/usr/bin/script -q "$LOG" /usr/bin/caffeinate -dims "$BIN" "${args[@]}" &
UPID=$!

# Optional VNC: once the page arms, poke a key and a click so event-to-rAF
# is a real input path, not a synthetic JS event (those are ignored).
VNC=${UML_VNC_DISPLAY:-127.0.0.1:5900}
vnc_poked=0
for i in $(seq 1 110); do
  if ! kill -0 "$UPID" 2>/dev/null; then break; fi
  if [ "$vnc_poked" -eq 0 ] && /usr/bin/grep -q "INTERACTIVE_READY_FOR_INPUT" "$LOG" 2>/dev/null; then
    echo "VNC_POKE $(date) display=$VNC" | tee -a "$LOG"
    if command -v vncdotool >/dev/null 2>&1; then
      vncdotool -s "$VNC" key a pause 0.3 click 1 || true
    else
      rfb=""
      for c in         "$HERE/macos-metal/vnc_rfb.py"         $HOME/linux-ios-bakeoff/notes/macos-metal-desktop/vnc_rfb.py         $HOME/linux-ios-bakeoff/notes/interactive-pack/scripts/macos-metal/vnc_rfb.py
      do
        [ -f "$c" ] && rfb=$c && break
      done
      if [ -n "$rfb" ]; then
        host=${VNC%:*}; port=${VNC##*:}
        python3 "$rfb" --host "$host" --port "$port" --key a --sleep 0.3 --click 960 400           >>"$LOG" 2>&1 || true
      else
        echo "VNC_POKE_SKIP no vncdotool or vnc_rfb.py" | tee -a "$LOG"
      fi
    fi
    vnc_poked=1
  fi
  if /usr/bin/grep -q "INTERACTIVE_DONE" "$LOG" 2>/dev/null; then
    # Give the serial a moment, then stop.
    sleep 2
    break
  fi
  sleep 1
done

if kill -0 "$UPID" 2>/dev/null; then
  uml_pids() { pgrep -f "$BIN" | while read -r pid; do
      comm=$(ps -p "$pid" -o comm= 2>/dev/null || true)
      case "$comm" in *uml-darwin*) echo "$pid" ;; esac
    done; }
  while read -r pid; do
    [ -n "$pid" ] || continue
    echo "TERM uml-darwin pid=$pid $(date)" | tee -a "$LOG"
    kill -TERM "$pid" 2>/dev/null || true
  done < <(uml_pids)
  for i in $(seq 1 40); do
    leftover=$(uml_pids)
    [ -z "$leftover" ] && break
    sleep 1
  done
  leftover=$(uml_pids)
  if [ -n "$leftover" ]; then
    echo "KILL leftover uml-darwin $leftover $(date)" | tee -a "$LOG"
    echo "$leftover" | xargs kill -KILL 2>/dev/null || true
  fi
  kill -TERM "$UPID" 2>/dev/null || true
  sleep 1
  kill -KILL "$UPID" 2>/dev/null || true
fi
kill "$MEMPID" 2>/dev/null || true
wait "$UPID" 2>/dev/null || true
echo "STOPPED $(date) tag=$TAG" | tee -a "$LOG"
rm -f "$FLAG" "$BROWSER_FILE"
echo "======= interactive summary =======" | tee -a "$LOG"
/usr/bin/grep -E 'INTERACTIVE_|DESKTOP_READY|FIREFOX_START|CHROMIUM_START|SWAP_ABORT' "$LOG" | tee -a "$LOG" || true
echo LOG="$LOG"
echo MEMLOG="$MEMLOG"
