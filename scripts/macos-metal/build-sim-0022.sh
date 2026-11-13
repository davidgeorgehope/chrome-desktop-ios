#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
export LANG=C
ROOT=/Users/davidhope/linux-ios-bakeoff/src/Kernarium-0022-clean
export ROOT_DIR="$ROOT"
NOTES=/Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop
UDID=8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB
LOG="$NOTES/build-sim-0022-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "BUILD_START $(date) log=$LOG root=$ROOT"
cd "$ROOT"
export UML_MAINLINE_618_KERNEL_ARTIFACT_DIR="$ROOT/.build/kernel/artifacts/mainline-6.18-arm64-4k-20261112-6.18.60-local2"
ARTIFACT="$UML_MAINLINE_618_KERNEL_ARTIFACT_DIR"
echo "ARTIFACT=$ARTIFACT"
test -d "$ARTIFACT"

echo "---- cmake configure kernarium-ios-simulator ----"
cmake --preset kernarium-ios-simulator \
  -DUML_MAINLINE_618_KERNEL_ARTIFACT_DIR="$ARTIFACT"
echo "CMAKE_CONFIGURE_OK $(date)"

echo "---- cmake build ----"
cmake --build --preset kernarium-ios-simulator --parallel 8
echo "CMAKE_BUILD_OK $(date)"

echo "---- package-ios-linux-device-and-simulator ----"
/bin/sh "$NOTES/package-ios-linux-device-and-simulator.sh"
echo "PACKAGE_OK $(date)"

echo "---- xcodebuild Simulator Peek iPhone 17 (build only) ----"
# codesign may fail in a non-Aqua SSH session; LaunchAgent path is used for test.
xcodebuild build \
  -project "$ROOT/Kernarium/Kernarium.xcodeproj" \
  -scheme Kernarium \
  -configuration Release \
  -destination "id=$UDID" \
  -derivedDataPath "$ROOT/.build/kernarium-simulator-derived" \
  -jobs 8 \
  CODE_SIGNING_ALLOWED=NO \
  EXCLUDED_ARCHS=x86_64 \
  DEVELOPMENT_TEAM=4P2629648N
echo "XCODEBUILD_OK $(date)"
APP="$ROOT/.build/kernarium-simulator-derived/Build/Products/Release-iphonesimulator/Kernarium.app"
ls -la "$APP/Kernarium"
plutil -p "$APP/Info.plist" | grep CFBundleIdentifier || true
echo ok > "$NOTES/build-sim-0022.status"
echo "BUILD_DONE $(date)"
echo "LOG=$LOG"
