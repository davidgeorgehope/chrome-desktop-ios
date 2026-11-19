#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
export LANG=C
# Official 0022 tree. Do not build from the dirty persist-v2 worktree.
ROOT=$HOME/linux-ios-bakeoff/src/Kernarium-0022-clean
export ROOT_DIR="$ROOT"
NOTES=$HOME/linux-ios-bakeoff/notes/macos-metal-desktop
LOG="$NOTES/build-d4ipad-0022-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "BUILD_START $(date) log=$LOG root=$ROOT"
cd "$ROOT"
# Official 0001 pins accepted-4k.env to local1; D4iPad 0021 and official
# uml-darwin 0022 were linked with host-page-aligned local2.
export UML_MAINLINE_618_KERNEL_ARTIFACT_DIR="$ROOT/.build/kernel/artifacts/mainline-6.18-arm64-4k-20261112-6.18.60-local2"
ARTIFACT="$UML_MAINLINE_618_KERNEL_ARTIFACT_DIR"
echo "ARTIFACT=$ARTIFACT"
test -d "$ARTIFACT"

echo "---- cmake configure UML_IOS_DEBUGGER_JIT=ON ----"
cmake --preset kernarium-ios-device \
  -DUML_MAINLINE_618_KERNEL_ARTIFACT_DIR="$ARTIFACT" \
  -DUML_IOS_DEBUGGER_JIT=ON
echo "CMAKE_CONFIGURE_OK $(date)"
grep -E "UML_IOS_DEBUGGER_JIT|UML_GPU_SOFTWARE_RENDERER" \
  "$ROOT/.build/kernarium-runtime-ios-device/CMakeCache.txt" || true

echo "---- cmake build ----"
cmake --build --preset kernarium-ios-device --parallel 8
echo "CMAKE_BUILD_OK $(date)"

echo "---- package-ios-linux-device ----"
/bin/sh "$NOTES/../package-ios-linux-device.sh"
echo "PACKAGE_OK $(date)"
echo "BUILD_DONE $(date)"
echo ok > "$NOTES/build-d4ipad-0022.status"
echo "LOG=$LOG"
