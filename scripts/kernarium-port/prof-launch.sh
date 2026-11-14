#!/bin/bash
# KBIN=path prof-launch.sh TAG [ENGINE]
# One uml-darwin, slim Alpine, mem=4G ncpus=4, 4G/128M, UML_JIT_PROFILE
# dumped at every ===PHASE=== marker. Logs under $LOGDIR (default
# /tmp/k-harness), not scratch. Guest scripts come from this directory.
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin LANG=C
HERE=$(cd "$(dirname "$0")" && pwd)
PACK=/Users/davidhope/linux-ios-bakeoff/notes/cpu-benches
LOGDIR=${LOGDIR:-/tmp/k-harness}
TAG=$1
BIN=${KBIN:?set KBIN to the uml-darwin binary}
ENG=${2:-jit}
MEM=${MEM:-4G}
NCPUS=${NCPUS:-4}
ROOTFS=/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-minimal.ext4
LOG=$LOGDIR/logs/$TAG.log
PD=$LOGDIR/logs/$TAG.prof
mkdir -p "$PD"
# Do not inherit leftover 2G k-boot env; callers override with MEM / CACHE_BUDGET.
export UML_PREFLIGHT_GUEST_MEM=$MEM
. /Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop/preflight-uml-darwin.sh
pgrep -f '[u]ml-darwin' >/dev/null && { echo "refuse: uml-darwin already running"; exit 2; }
unset UML_JIT_PERSISTENT_CACHE UML_JIT_PERSISTENT_CACHE_SOURCE
unset KERNARIUM_JIT_PERSISTENT_CACHE KERNARIUM_JIT_PERSISTENT_CACHE_SOURCE
unset UML_JIT_SHARED_PIC
export UML_JIT_CACHE_BUDGET=${CACHE_BUDGET:-4G}
export UML_JIT_EXECUTOR_CACHE_BUDGET=${EXECUTOR_BUDGET:-128M}
APKS=${APKS:-$PACK/apks.tar}
if [ ! -f "$APKS" ]; then
  APKS=/tmp/k-harness/apks.tar
fi
if [ ! -f "$APKS" ]; then
  echo "missing apks.tar (set APKS=...)" >&2
  exit 2
fi
if [ -n "${SIGPROF:-}" ]; then
  export UML_JIT_SIGPROF=1 UML_JIT_SIGPROF_HZ=${SIGPROF} UML_JIT_SIGPROF_FILE=$PD/hist.txt
fi
export UML_JIT_PROFILE=1
export UML_JIT_PROFILE_FILE=$PD/cur.txt
export UML_JIT_PROFILE_CONTROL=$PD/ctl
echo "LAUNCH $(date) tag=$TAG bin=$BIN md5=$(md5 -q "$BIN") engine=$ENG mem=$MEM ncpus=$NCPUS budget=${UML_JIT_CACHE_BUDGET}/${UML_JIT_EXECUTOR_CACHE_BUDGET} pic=${UML_JIT_SHARED_PIC:-0} ${PROF_EXTRA:-}" > "$LOG"
: > "$PD/phases.txt"
( tail -n 0 -F "$LOG" 2>/dev/null | while IFS= read -r line; do
    case "$line" in *===PHASE===*|*===T===*|*===INFO===*)
      echo "$(date +%H:%M:%S) $line" | tr -d '\r' >> "$PD/phases.txt"
      case "$line" in *===PHASE===*)
        ph=$(echo "$line" | tr -d '\r' | awk '{print $2}')
        sleep 1.3
        cp -f "$PD/cur.txt" "$PD/at-$ph.txt" 2>/dev/null
        [ -n "${SIGPROF:-}" ] && cp -f "$PD/hist.txt" "$PD/hist-at-$ph.txt" 2>/dev/null
        ;;
      esac
      ;;
    esac
  done ) &
W=$!
( for i in $(seq 1 600); do
    used=$(sysctl vm.swapusage | sed -n 's/.*used = \([0-9.][0-9.]*\)M.*/\1/p')
    awk -v u="${used:-0}" -v s="${UML_SWAP_USED_AT_START:-0}" 'BEGIN { exit (u+0 > s+0 + 2048) }' || {
      echo "SWAP_ABORT used=${used}M $(date)" >> "$LOG"
      pgrep -f "^$BIN " | xargs kill -TERM 2>/dev/null
      break
    }
    sleep 2
  done ) &
G=$!
/usr/bin/script -q -F -a "$LOG" /opt/homebrew/bin/timeout 1500 /usr/bin/caffeinate -i "$BIN" --execution-engine="$ENG" \
  --guest-file=/boot.env="$PACK/boot.env" \
  --guest-file=/payload/usr/local/bin/run-benches.sh="$HERE/${GUEST:-guest-prof.sh}" \
  --guest-file=/payload/usr/local/share/cpu-benches/cmp-benches.sh="$HERE/cmp-benches.sh" \
  --guest-file=/payload/usr/local/share/cpu-benches/apks.tar="$APKS" \
  mem="$MEM" ncpus="$NCPUS" ubd0c="$ROOTFS" rootfstype=ext4 > /dev/null 2>&1 < /dev/null
kill "$G" 2>/dev/null; sleep 1; kill "$W" 2>/dev/null
pkill -f "tail -n 0 -F $LOG" 2>/dev/null || true
echo "STOPPED $(date)" >> "$LOG"
grep -E "===T===|INFO" "$PD/phases.txt" || true
