#!/bin/bash
# Fetch StikJIT 2.0.1 (MPL-2.0, github.com/StikDebug/StikJIT) as an
# xcframework. Pinned to the SHA-256 GitHub publishes for that release.
# Used only by the DeskBrowser JIT helper extension. Not committed.
set -euo pipefail
VERSION=2.0.1
SHA256=c376687326a785f5ed1da8caca08adc709b56919019dd751bca059b92b175d95
URL="https://github.com/StikDebug/StikJIT/releases/download/$VERSION/StikJIT.xcframework.zip"
DEST="${1:-$HOME/chromium-build/Frameworks}"
if [ "$(cat "$DEST/StikJIT.version" 2>/dev/null || true)" = "$VERSION" ] && [ -d "$DEST/StikJIT.xcframework" ]; then
  echo "StikJIT $VERSION already in $DEST"
  exit 0
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl --fail --location --silent --show-error --output "$WORK/StikJIT.zip" "$URL"
echo "$SHA256  $WORK/StikJIT.zip" | shasum -a 256 --check --quiet
mkdir "$WORK/out"
ditto -x -k "$WORK/StikJIT.zip" "$WORK/out"
[ -d "$WORK/out/StikJIT.xcframework" ] || { echo "no StikJIT.xcframework in the zip" >&2; exit 1; }
mkdir -p "$DEST"
rm -rf "$DEST/StikJIT.xcframework"
mv "$WORK/out/StikJIT.xcframework" "$DEST/"
echo "$VERSION" > "$DEST/StikJIT.version"
echo "StikJIT $VERSION in $DEST"
