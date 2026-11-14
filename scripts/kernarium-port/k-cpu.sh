#!/bin/bash
# k-cpu.sh TAG : official uml-darwin 0022, slim Alpine, 4 CPUs / 4G, cmp-benches.sh twice (swap guard as launch-benches-bin.sh).
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin LANG=C
D=/Users/davidhope/linux-ios-bakeoff/scratch/jitprof; PACK=/Users/davidhope/linux-ios-bakeoff/notes/cpu-benches
BIN=$KBIN
ROOTFS=/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-minimal.ext4
LOG=$D/logs/$1.log; mkdir -p $D/logs
export UML_PREFLIGHT_GUEST_MEM=4G
. /Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop/preflight-uml-darwin.sh
pgrep -f '[c]rate-run --' >/dev/null && { echo "refuse: crate running"; exit 2; }
unset UML_JIT_PERSISTENT_CACHE UML_JIT_PERSISTENT_CACHE_SOURCE KERNARIUM_JIT_PERSISTENT_CACHE KERNARIUM_JIT_PERSISTENT_CACHE_SOURCE
export UML_JIT_CACHE_BUDGET=4G UML_JIT_EXECUTOR_CACHE_BUDGET=128M
echo "LAUNCH $(date) tag=$1 bin=$BIN mem=4G ncpus=4 budget=4G/128M md5=$(md5 -q $BIN)" > $LOG
( for i in $(seq 1 300); do
    used=$(sysctl vm.swapusage | sed -n 's/.*used = \([0-9.][0-9.]*\)M.*/\1/p')
    awk -v u="${used:-0}" -v s="${UML_SWAP_USED_AT_START:-0}" 'BEGIN { exit (u+0 > s+0 + 2048) }' || {
      echo "SWAP_ABORT used=${used}M $(date)" >> $LOG
      pgrep -f "^$BIN " | xargs kill -TERM 2>/dev/null; break; }
    sleep 2; done ) &
G=$!
/usr/bin/script -q -a $LOG /usr/bin/caffeinate -i "$BIN" --execution-engine=jit \
  --guest-file=/boot.env="$PACK/boot.env" \
  --guest-file=/payload/usr/local/bin/run-benches.sh="$D/k-guest-cmpb.sh" \
  --guest-file=/payload/usr/local/share/cpu-benches/cmp-benches.sh="$D/cmp-benches.sh" \
  --guest-file=/payload/usr/local/share/cpu-benches/apks.tar="$PACK/apks.tar" \
  mem=4G ncpus=4 ubd0c="$ROOTFS" rootfstype=ext4 > /dev/null 2>&1 < /dev/null
kill $G 2>/dev/null
echo "STOPPED $(date)" >> $LOG
grep -aE "===CMPB" $LOG | tr -d '\r' | awk '!s[$0]++ || /CMPB=== /'
