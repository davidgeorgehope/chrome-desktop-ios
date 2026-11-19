#!/bin/bash
# Attach ~/linux-ios-bakeoff/KernariumCS.sparseimage at login.
# The image is not encrypted; this script never touches the Keychain or
# the `security` CLI. Idempotent if the volume is already mounted.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

IMAGE="${KERNARIUMCS_IMAGE:-$HOME/linux-ios-bakeoff/KernariumCS.sparseimage}"
MOUNT="${KERNARIUMCS_MOUNT:-/Volumes/KernariumCS}"
LOG="${KERNARIUMCS_LOG:-$HOME/Library/Logs/kernariumcs-attach.log}"
mkdir -p "$(dirname "$LOG")"
ts() { date '+%Y-%m-%d %H:%M:%S %Z'; }

if [ ! -f "$IMAGE" ]; then
	echo "$(ts) missing image $IMAGE" >>"$LOG"
	exit 1
fi
if [ -d "$MOUNT" ] && [ -w "$MOUNT" ] || [ -d "$MOUNT/rootfs" ]; then
	echo "$(ts) already mounted at $MOUNT" >>"$LOG"
	exit 0
fi

# Retry: diskimages-helper may not be ready at the very start of Aqua login.
for attempt in 1 2 3 4 5; do
	if /usr/bin/hdiutil attach -nobrowse -noautoopen -owners on "$IMAGE" >>"$LOG" 2>&1; then
		if [ -d "$MOUNT" ]; then
			echo "$(ts) attached $IMAGE at $MOUNT (attempt $attempt)" >>"$LOG"
			exit 0
		fi
	fi
	# Already attached under a different path or race with a manual attach.
	if [ -d "$MOUNT" ]; then
		echo "$(ts) mount appeared after attempt $attempt" >>"$LOG"
		exit 0
	fi
	sleep $((attempt * 2))
done
echo "$(ts) failed to attach $IMAGE" >>"$LOG"
exit 1
