#!/bin/bash
set -euo pipefail
SRC=/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-minimal.ext4
SCRIPT=$HOME/linux-ios-bakeoff/notes/guest-run-benches.sh
WORK=/home/guest/alpine-console.ext4
MNT=/home/guest/mnt-alpine

echo "==== PATCH START $(date) ===="
chmod u+w "$SRC" || true
# copy off virtiofs onto Lima's ext4 disk
limactl shell kernarium-linux -- sudo -n bash -c "
set -euo pipefail
rm -rf $MNT
mkdir -p $MNT
cp -f $SRC $WORK
sync
e2fsck -fy $WORK || true
mount -o loop $WORK $MNT
mkdir -p $MNT/usr/local/bin
cp -f $SCRIPT $MNT/usr/local/bin/run-benches.sh
chmod 755 $MNT/usr/local/bin/run-benches.sh
# rewrite inittab: OpenRC then once benches; gettys started by the script
cat > $MNT/etc/inittab << 'IN'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
::once:/usr/local/bin/run-benches.sh
::shutdown:/sbin/openrc shutdown
IN
echo '---- inittab ----'
cat $MNT/etc/inittab
echo '---- script installed ----'
ls -l $MNT/usr/local/bin/run-benches.sh
umount $MNT
e2fsck -fy $WORK || true
cp -f $WORK $SRC
sync
echo COPY_BACK_OK
"
chmod u+w "$SRC" || true
ls -l "$SRC"
echo "==== PATCH OK $(date) ===="
