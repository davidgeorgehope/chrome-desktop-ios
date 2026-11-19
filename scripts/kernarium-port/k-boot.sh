#!/bin/bash
# k-boot.sh TAG
# Boot uml-darwin far enough to see whether /init can mount devtmpfs, then
# kill the VM. Logs go under $LOGDIR (default /tmp/k-harness), not scratch.
# Required: KBIN. Optional: UML_JIT_SHARED_PIC, mem/ncpus (default 2G/2),
# UML_PREFLIGHT_GUEST_MEM (default matches mem).
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin LANG=C
PACK=$HOME/linux-ios-bakeoff/notes/cpu-benches
ROOTFS=/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-minimal.ext4
LOGDIR=${LOGDIR:-/tmp/k-harness}
BIN=${KBIN:?set KBIN to the uml-darwin binary}
MEM=${MEM:-2G}
NCPUS=${NCPUS:-2}
TIMEOUT=${TIMEOUT:-25}
mkdir -p "$LOGDIR"
LOG=$LOGDIR/${1:?tag}.log
export UML_PREFLIGHT_GUEST_MEM=${UML_PREFLIGHT_GUEST_MEM:-$MEM}
. $HOME/linux-ios-bakeoff/notes/macos-metal-desktop/preflight-uml-darwin.sh
pgrep -f '[u]ml-darwin' >/dev/null && { echo "refuse: uml-darwin already running"; exit 2; }
unset UML_JIT_PERSISTENT_CACHE UML_JIT_PERSISTENT_CACHE_SOURCE
unset KERNARIUM_JIT_PERSISTENT_CACHE KERNARIUM_JIT_PERSISTENT_CACHE_SOURCE
export UML_JIT_CACHE_BUDGET=${UML_JIT_CACHE_BUDGET:-2G}
export UML_JIT_EXECUTOR_CACHE_BUDGET=${UML_JIT_EXECUTOR_CACHE_BUDGET:-64M}
echo "LAUNCH $(date) tag=$1 bin=$BIN pic=${UML_JIT_SHARED_PIC:-0} mem=$MEM ncpus=$NCPUS md5=$(md5 -q "$BIN")" > "$LOG"
( sleep "$TIMEOUT"; pgrep -f "[u]ml-darwin" | xargs kill -TERM 2>/dev/null ) &
WATCH=$!
/usr/bin/script -q -a "$LOG" /usr/bin/caffeinate -i "$BIN" --execution-engine=jit \
  --guest-file=/boot.env="$PACK/boot.env" \
  mem="$MEM" ncpus="$NCPUS" ubd0c="$ROOTFS" rootfstype=ext4 < /dev/null >/dev/null
kill "$WATCH" 2>/dev/null || true
echo "STOPPED $(date)" >> "$LOG"
grep -aE 'segfault|BOOT_ERROR|panic|PIC_BAD_PC|Run /init|devtmpfs' "$LOG" | tr -d '\r' | awk '!s[$0]++' | head
