#!/bin/bash
# One-shot Aqua gui/501 LaunchAgent for D4iPad xcodebuild/codesign.
# Not installed under ~/Library/LaunchAgents (would rerun at login).
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export LANG=C
TAG="${1:-ff}"
ROOTFS="${2:-alpine-3.24.2-desktop-labwc.ext4}"
NOTES=/Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop
LABEL=com.davidhope.d4ipad-0022
SRC="$NOTES/com.davidhope.d4ipad-0022.plist"
PLIST="/tmp/com.davidhope.d4ipad-0022-$TAG.plist"
# rewrite arguments
/usr/bin/sed -e "s/PLACEHOLDER_TAG/$TAG/" -e "s/PLACEHOLDER_ROOTFS/$ROOTFS/" "$SRC" > "$PLIST"
echo "BOOTSTRAP $(date) label=$LABEL tag=$TAG rootfs=$ROOTFS plist=$PLIST"
launchctl bootout "gui/501/$LABEL" 2>/dev/null || true
# reset last-exit so waiters do not see a previous run
rm -f "$NOTES/d4ipad-0022-last-exit.txt"
: > /Users/davidhope/Library/Logs/d4ipad-0022-launch.stdout.log
: > /Users/davidhope/Library/Logs/d4ipad-0022-launch.stderr.log
launchctl bootstrap gui/501 "$PLIST"
echo "BOOTSTRAPPED $(date)"
echo "PLIST=$PLIST"
