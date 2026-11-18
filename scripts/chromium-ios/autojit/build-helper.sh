#!/bin/bash
# Build an unsigned DeskBrowserJITHelper.appex against the pinned StikJIT
# xcframework. Signing and header-stripped embed happen in
# sign-chrome-ios-device-autojit.sh. Cleans previous products first.
set -euo pipefail
export TMPDIR=/tmp
ROOT="${AUTOJIT_ROOT:-$HOME/chromium-build/autojit}"
FWDEST="${STIKJIT_DEST:-$HOME/chromium-build/Frameworks}"
OUT="${HELPER_OUT:-$HOME/chromium-build/jit-helper}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Prefer the in-tree fetch script; fall back if this is a copied tree.
FETCH="$SCRIPT_DIR/fetch-stikjit.sh"
[ -x "$FETCH" ] || FETCH="$ROOT/fetch-stikjit.sh"
"$FETCH" "$FWDEST"

# Make the project's SOURCE_ROOT file ref resolve.
rm -rf "$OUT" "$ROOT/DerivedData"
mkdir -p "$OUT" "$ROOT"
# Keep sources where the xcodeproj expects them. If we're running from the
# repo copy, use it; otherwise expect a copy at $ROOT.
PROJ_DIR="$SCRIPT_DIR"
[ -d "$PROJ_DIR/DeskBrowserJITHelper.xcodeproj" ] || PROJ_DIR="$ROOT"
ln -sfn "$FWDEST/StikJIT.xcframework" "$PROJ_DIR/StikJIT.xcframework"

# Clean stale signed copies so an old StikJIT signature cannot sneak in.
rm -rf "$OUT/DeskBrowserJITHelper.appex" \
       "$PROJ_DIR/DerivedData/Build/Products"

xcodebuild -project "$PROJ_DIR/DeskBrowserJITHelper.xcodeproj" \
  -scheme DeskBrowserJITHelper \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$PROJ_DIR/DerivedData" \
  STIKJIT_XCFRAMEWORK="$FWDEST/StikJIT.xcframework" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APPEX=$(find "$PROJ_DIR/DerivedData/Build/Products" -name 'DeskBrowserJITHelper.appex' -type d | head -1)
[ -d "$APPEX" ] || { echo "xcodebuild did not produce the helper appex" >&2; exit 1; }
# Fresh copy with no stale signature or headers in a nested StikJIT.
rm -rf "$OUT/DeskBrowserJITHelper.appex"
ditto "$APPEX" "$OUT/DeskBrowserJITHelper.appex"
rm -rf "$OUT/DeskBrowserJITHelper.appex/_CodeSignature" \
       "$OUT/DeskBrowserJITHelper.appex/Frameworks"
echo "HELPER_APPEX $OUT/DeskBrowserJITHelper.appex"
