#!/bin/bash
# KBIN=path prof-launch.sh TAG [ENGINE]: one uml-darwin, slim Alpine, mem=4G ncpus=4, 4G/128M,
# UML_JIT_PROFILE dumped at every ===PHASE=== marker. Swap guard as k-cpu.sh.
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin LANG=C
D=/Users/davidhope/linux-ios-bakeoff/scratch/jitprof; PACK=/Users/davidhope/linux-ios-bakeoff/notes/cpu-benches
TAG=$1; BIN=$KBIN; ENG=${2:-jit}
ROOTFS=/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-minimal.ext4
LOG=$D/logs/$TAG.log; PD=$D/logs/$TAG.prof; mkdir -p $PD
export UML_PREFLIGHT_GUEST_MEM=4G
. /Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop/preflight-uml-darwin.sh
unset UML_JIT_PERSISTENT_CACHE UML_JIT_PERSISTENT_CACHE_SOURCE KERNARIUM_JIT_PERSISTENT_CACHE KERNARIUM_JIT_PERSISTENT_CACHE_SOURCE
export UML_JIT_CACHE_BUDGET=4G UML_JIT_EXECUTOR_CACHE_BUDGET=128M
[ -n "${SIGPROF:-}" ] && export UML_JIT_SIGPROF=1 UML_JIT_SIGPROF_HZ=${SIGPROF} UML_JIT_SIGPROF_FILE=$PD/hist.txt
export UML_JIT_PROFILE=1 UML_JIT_PROFILE_FILE=$PD/cur.txt UML_JIT_PROFILE_CONTROL=$PD/ctl
echo "LAUNCH $(date) tag=$TAG bin=$BIN md5=$(md5 -q $BIN) engine=$ENG mem=4G ncpus=4 budget=4G/128M ${PROF_EXTRA:-}" > $LOG
: > $PD/phases.txt
( tail -n 0 -F $LOG 2>/dev/null | while IFS= read -r line; do
    case "$line" in *===PHASE===*|*===T===*|*===INFO===*)
      echo "$(date +%H:%M:%S) $line" | tr -d '\r' >> $PD/phases.txt
      case "$line" in *===PHASE===*) ph=$(echo "$line" | tr -d '\r' | awk '{print $2}')
        sleep 1.3; cp -f $PD/cur.txt "$PD/at-$ph.txt" 2>/dev/null; [ -n "${SIGPROF:-}" ] && cp -f $PD/hist.txt "$PD/hist-at-$ph.txt" 2>/dev/null;; esac;;
    esac; done ) &
W=$!
( for i in $(seq 1 600); do
    used=$(sysctl vm.swapusage | sed -n 's/.*used = \([0-9.][0-9.]*\)M.*/\1/p')
    awk -v u="${used:-0}" -v s="${UML_SWAP_USED_AT_START:-0}" 'BEGIN { exit (u+0 > s+0 + 2048) }' || {
      echo "SWAP_ABORT used=${used}M $(date)" >> $LOG; pkill -TERM -f "^$BIN " ; break; }
    sleep 2; done ) &
G=$!
/usr/bin/script -q -F -a $LOG /opt/homebrew/bin/timeout 1500 /usr/bin/caffeinate -i "$BIN" --execution-engine=$ENG \
  --guest-file=/boot.env="$PACK/boot.env" \
  --guest-file=/payload/usr/local/bin/run-benches.sh="$D/${GUEST:-guest-prof.sh}" \
  --guest-file=/payload/usr/local/share/cpu-benches/cmp-benches.sh="$D/cmp-benches.sh" \
  --guest-file=/payload/usr/local/share/cpu-benches/apks.tar="$PACK/apks.tar" \
  mem=4G ncpus=4 ubd0c="$ROOTFS" rootfstype=ext4 > /dev/null 2>&1 < /dev/null
kill $G 2>/dev/null; sleep 1; kill $W 2>/dev/null; pkill -f "tail -n 0 -F $LOG" 2>/dev/null
echo "STOPPED $(date)" >> $LOG
cat $PD/phases.txt | grep -E "===T===|INFO"
