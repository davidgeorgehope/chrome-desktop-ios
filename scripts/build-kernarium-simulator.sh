#!/bin/bash
# Rebuild Kernarium for the iOS Simulator from a Kernarium checkout, with the
# iOS-applicable JIT series (0013 = evict + packed publish + bump arena),
# the Simulator SDK vm_region_64 fix (0014), and the optional
# KERNARIUM_JIT_CACHE_BUDGET override (0015).
#
# This script does not build the macos-integration preset, does not touch the
# official uml-darwin identity, and does not install anything on a physical
# iPhone. It only produces a Release-iphonesimulator Kernarium.app.
#
# Usage:
#   scripts/build-kernarium-simulator.sh /path/to/Kernarium
#   KERNARIUM=/path/to/Kernarium scripts/build-kernarium-simulator.sh
#
# Optional:
#   DESTINATION=id=<udid>   default: generic/platform=iOS Simulator
#   JOBS=8
#   SKIP_PATCH=1            use sources already in the checkout
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin${PATH:+:$PATH}"

HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KERNARIUM=${1:-${KERNARIUM:-}}
if [ -z "$KERNARIUM" ]; then
  echo "usage: $0 /path/to/Kernarium" >&2
  exit 2
fi
KERNARIUM=$(CDPATH= cd -- "$KERNARIUM" && pwd)
if [ ! -f "$KERNARIUM/darwin/cpu/arm64/jit/jit_shared_translations.cpp" ] ||
   [ ! -f "$KERNARIUM/Kernarium/Kernarium.xcodeproj/project.pbxproj" ]; then
  echo "not a Kernarium checkout: $KERNARIUM" >&2
  exit 2
fi

DESTINATION=${DESTINATION:-generic/platform=iOS Simulator}
JOBS=${JOBS:-8}
DERIVED=${DERIVED:-$KERNARIUM/.build/kernarium-simulator-derived}
RUNTIME_BUILD=$KERNARIUM/.build/kernarium-runtime-ios-simulator/Kernarium/Runtime
OUT_XC=$KERNARIUM/.build/kernarium-xcframeworks
APP=$DERIVED/Build/Products/Release-iphonesimulator/Kernarium.app

echo "==== START $(date) checkout=$KERNARIUM ===="
echo "NOTE: do not rebuild official macos uml-darwin from these sources."
echo "NOTE: do not install the resulting app on a physical iPhone."

if [ "${SKIP_PATCH:-0}" != 1 ]; then
  echo "---- apply 0013 JIT sources (evict + packed + arena) ----"
  src13=$HERE/patches/0013-jit-publish-arena
  for f in jit_shared_translations.cpp jit_shared_translations.hpp jit_executor_cache.cpp; do
    if [ ! -f "$src13/$f" ]; then
      echo "missing $src13/$f" >&2
      exit 2
    fi
    cp -f "$src13/$f" "$KERNARIUM/darwin/cpu/arm64/jit/$f"
  done
  echo "---- apply 0014 vm_region_64 ----"
  src14=$HERE/patches/0014-simulator-vm-region-64/user_map.cpp
  if [ ! -f "$src14" ]; then
    echo "missing $src14" >&2
    exit 2
  fi
  cp -f "$src14" "$KERNARIUM/darwin/memory/mmu/user_map.cpp"
  echo "---- apply 0015 KERNARIUM_JIT_CACHE_BUDGET ----"
  src15=$HERE/patches/0015-kernarium-jit-cache-budget/jit_cache_budget_for.patch
  if [ ! -f "$src15" ]; then
    echo "missing $src15" >&2
    exit 2
  fi
  if grep -q KERNARIUM_JIT_CACHE_BUDGET "$KERNARIUM/darwin/runtime/context.cpp"; then
    echo "0015 already present in context.cpp"
  else
    patch -p1 -d "$KERNARIUM" --forward < "$src15"
  fi
  echo "PATCH_OK $(date)"
else
  echo "---- SKIP_PATCH=1; using checkout sources as-is ----"
fi

echo "---- cmake --build --preset kernarium-ios-simulator ----"
cd "$KERNARIUM"
# Never the macos-integration preset.
cmake --build --preset kernarium-ios-simulator
echo "CMAKE_OK $(date)"

echo "---- package KRuntime_6_18_4K.xcframework (Simulator only) ----"
SIM_RT=$RUNTIME_BUILD/KRuntime_6_18_4K.framework
SIM_RT_DSYM=$RUNTIME_BUILD/KRuntime_6_18_4K.framework.dSYM
if [ ! -d "$SIM_RT" ]; then
  echo "missing $SIM_RT" >&2
  exit 1
fi
STAGE=$(mktemp -d "$KERNARIUM/.build/.kernarium-xcframeworks.XXXXXX")
if [ -d "$SIM_RT_DSYM" ]; then
  xcodebuild -create-xcframework \
    -framework "$SIM_RT" -debug-symbols "$SIM_RT_DSYM" \
    -output "$STAGE/KRuntime_6_18_4K.xcframework"
else
  xcodebuild -create-xcframework \
    -framework "$SIM_RT" \
    -output "$STAGE/KRuntime_6_18_4K.xcframework"
fi
mkdir -p "$OUT_XC"
rm -rf "$OUT_XC/KRuntime_6_18_4K.xcframework"
mv "$STAGE/KRuntime_6_18_4K.xcframework" "$OUT_XC/"
rmdir "$STAGE" || rm -rf "$STAGE"
echo "PACKAGE_OK $(date) MesaEGL/MesaGallium are reused if already present in $OUT_XC"

echo "---- xcodebuild (iphonesimulator only) ----"
xcodebuild build \
  -project "$KERNARIUM/Kernarium/Kernarium.xcodeproj" \
  -scheme Kernarium \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  -jobs "$JOBS" \
  CODE_SIGNING_ALLOWED=NO \
  EXCLUDED_ARCHS=x86_64
echo "XCODEBUILD_OK $(date)"

if [ ! -d "$APP" ]; then
  echo "missing $APP" >&2
  exit 1
fi
echo "APP $APP"
echo "==== BUILD_OK $(date) ===="
