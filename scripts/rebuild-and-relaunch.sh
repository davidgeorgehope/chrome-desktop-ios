#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
ROOT=/Users/davidhope/linux-ios-bakeoff
K=$ROOT/src/Kernarium
UDID=8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB
BUNDLE=com.imxieyi.Kernarium
LOG=$ROOT/notes/rebuild-and-relaunch.log
exec >>"$LOG" 2>&1
echo "==== START $(date) ===="

echo "---- cmake runtime ----"
cd "$K"
cmake --build --preset kernarium-ios-simulator
echo "CMAKE_OK $(date)"

echo "---- package xcframework ----"
SIM_RT="$K/.build/kernarium-runtime-ios-simulator/Kernarium/Runtime/KRuntime_6_18_4K.framework"
SIM_RT_DSYM="$K/.build/kernarium-runtime-ios-simulator/Kernarium/Runtime/KRuntime_6_18_4K.framework.dSYM"
OUT="$K/.build/kernarium-xcframeworks"
STAGE=$(mktemp -d "$K/.build/.kernarium-xcframeworks.XXXXXX")
xcodebuild -create-xcframework \
  -framework "$SIM_RT" -debug-symbols "$SIM_RT_DSYM" \
  -output "$STAGE/KRuntime_6_18_4K.xcframework"
rm -rf "$OUT/KRuntime_6_18_4K.xcframework"
mv "$STAGE/KRuntime_6_18_4K.xcframework" "$OUT/"
rmdir "$STAGE" || rm -rf "$STAGE"
echo "PACKAGE_OK $(date)"

echo "---- xcodebuild ----"
xcodebuild build \
  -project "$K/Kernarium/Kernarium.xcodeproj" \
  -scheme Kernarium \
  -destination "id=$UDID" \
  -derivedDataPath "$K/.build/kernarium-simulator-derived" \
  -jobs 8 \
  CODE_SIGNING_ALLOWED=NO \
  EXCLUDED_ARCHS=x86_64
echo "XCODEBUILD_OK $(date)"

APP="$K/.build/kernarium-simulator-derived/Build/Products/Release-iphonesimulator/Kernarium.app"
rm -rf "$ROOT/bundles/Kernarium.app"
ditto "$APP" "$ROOT/bundles/Kernarium.app"

echo "---- install and launch ----"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
mkdir -p "$CONTAINER/Documents"
ln -sfn /Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-minimal.ext4 \
  "$CONTAINER/Documents/alpine-3.24.2-minimal.ext4"
# briefly capture console
SIMCTL_CHILD_KERNARIUM_ROOTFS=alpine-3.24.2-minimal.ext4 \
  xcrun simctl launch --console-pty "$UDID" "$BUNDLE" \
  > "$ROOT/notes/kernarium-sim-launch-2.log" 2>&1 &
sleep 6
xcrun simctl io "$UDID" screenshot "$ROOT/screenshots/kernarium-02-relaunched.png"
echo "---- launch log ----"
cat "$ROOT/notes/kernarium-sim-launch-2.log"
echo "==== RELAUNCH_OK $(date) ===="
