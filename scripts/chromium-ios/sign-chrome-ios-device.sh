#!/bin/bash
# Signs out/Release-iphoneos/Chromium.app for David's iPhone with team
# YOURTEAMID (Apple Development identity) and packs Chromium-device.ipa.
# Single-process build: BrowserEngineKit child-process extensions (Extensions/)
# and app extensions (PlugIns/) are dropped since we lack the
# web-browser-engine / app-group entitlements. Uses the team wildcard
# development profile (it lists the phone). No security CLI.
set -euo pipefail
SRC=${CHROMIUM_SRC:-$HOME/chromium-build/chromium/src}
OUT=${CHROMIUM_OUT:-$SRC/out/Release-iphoneos}
TEAM=${TEAM_ID:?set TEAM_ID to your Apple team ID}
IDENTITY=${SIGN_IDENTITY:?set SIGN_IDENTITY to your Apple Development identity SHA-1}
PROFILE=${PROFILE:-$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/4d14b35d-df44-468b-89a4-dac7d68e4362.mobileprovision}
STAGE=$OUT/device-sign
IPA=$OUT/Chromium-device.ipa
rm -rf "$STAGE"; mkdir -p "$STAGE/Payload"
ditto "$OUT/Chromium.app" "$STAGE/Payload/Chromium.app"
APP=$STAGE/Payload/Chromium.app
rm -rf "$APP/PlugIns" "$APP/Extensions" "$APP/_CodeSignature"
find "$APP" -name _CodeSignature -prune -exec rm -rf {} +
cp "$PROFILE" "$APP/embedded.mobileprovision"
BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
ENT=$STAGE/app.entitlements
cat > "$ENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$TEAM.$BID</string>
<key>com.apple.developer.team-identifier</key><string>$TEAM</string>
<key>get-task-allow</key><true/>
<key>keychain-access-groups</key><array><string>$TEAM.$BID</string></array>
</dict></plist>
EOF
for fw in "$APP"/Frameworks/*.framework "$APP"/Frameworks/*.dylib; do
  [ -e "$fw" ] || continue
  codesign --force --timestamp=none --sign "$IDENTITY" "$fw"
done
codesign --force --timestamp=none --sign "$IDENTITY" --entitlements "$ENT" "$APP"
codesign --verify --deep --strict "$APP"
# Every nested bundle / Mach-O must verify on its own too.
while IFS= read -r b; do
  codesign --verify --strict "$b" || { echo "VERIFY_FAILED $b"; exit 3; }
done < <(find "$APP" \( -name '*.framework' -o -name '*.appex' -o -name '*.dylib' \) -prune -print)
codesign -d --entitlements :- "$APP" 2>/dev/null | head -40
rm -f "$IPA"
(cd "$STAGE" && /usr/bin/zip -qry "$IPA" Payload)
ls -l "$IPA"
echo "SIGNED_IPA $IPA bundle=$BID"
