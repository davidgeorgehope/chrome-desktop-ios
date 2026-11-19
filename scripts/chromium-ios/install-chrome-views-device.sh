#!/bin/bash
# Install ChromeDesktop-device.ipa (com.davidhope.deskbrowser.chromeviews) on
# David's iPhone 16 Pro with devicectl, then confirm via the app list. Only run
# with David's explicit go-ahead. Leaves com.davidhope.deskbrowser.blink alone.
set -euo pipefail
export PATH=/opt/homebrew/bin:$PATH
UDID=${PHONE_UDID:?set PHONE_UDID}
IPA=${IPA:-$HOME/chromium-build/chromium/src/out/Release-iphoneos-views/ChromeDesktop-device.ipa}
L=$HOME/chromium-build/logs/views-device/install-$(date +%H%M%S).log
echo "log $L"
timeout 600 xcrun devicectl device install app --device "$UDID" "$IPA" > "$L" 2>&1
timeout 120 xcrun devicectl device info apps --device "$UDID" --json-output /tmp/apps.json >/dev/null
python3 - <<'PY'
import json
apps=json.load(open("/tmp/apps.json"))["result"]["apps"]
ids={a.get("bundleIdentifier"):a for a in apps}
a=ids.get("com.davidhope.deskbrowser.chromeviews")
print("INSTALLED", a["name"], a.get("version")) if a else exit("NOT_INSTALLED")
print("blink present:", "com.davidhope.deskbrowser.blink" in ids)
PY
