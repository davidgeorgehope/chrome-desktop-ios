#!/bin/bash
# Prefetch the libghostty-spm binary xcframework so Xcode does not hang on the remote zip.
# Checksum is the published 1.6.20260922 artifact. Do not commit the zip or xcframework.
set -euo pipefail
ROOT="${1:-$HOME/linux-ios-bakeoff}"
K="$ROOT/src/Kernarium"
VER=1.6.20260922
SUM=804d4c92cad153eb8d85ed86f4c98ca587e90ff47ac0a62c846c985ece02a9c3
CACHE="$ROOT/cache/GhosttyKit.xcframework.zip"
URL="https://github.com/ghostty-org/libghostty-spm/releases/download/${VER}/GhosttyKit.xcframework.zip"
mkdir -p "$ROOT/cache"
if [[ ! -f "$CACHE" ]]; then
  curl -L --fail -o "$CACHE" "$URL"
fi
GOT=$(shasum -a 256 "$CACHE" | awk '{print $1}')
if [[ "$GOT" != "$SUM" ]]; then
  echo "checksum mismatch: $GOT" >&2
  exit 1
fi
# Expect a git checkout of libghostty-spm at $K/vendor/libghostty-spm
# with Package.local.swift selecting the local binary target.
DEST="$K/vendor/libghostty-spm/BinaryTarget"
mkdir -p "$DEST"
rm -rf "$DEST/GhosttyKit.xcframework"
ditto -x -k "$CACHE" "$DEST"
echo "vendored GhosttyKit.xcframework from $CACHE"
