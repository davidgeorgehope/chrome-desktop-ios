#!/bin/bash
# Sign the desktop Views app (out/Release-iphoneos-views/chrome_views_ios.app)
# as com.davidhope.deskbrowser.chromeviews so it installs beside Chromium.app
# (com.davidhope.deskbrowser.blink). Uses the explicit App ID profile minted by
# chromeviews-appid-stub (increased-memory-limit + extended-virtual-addressing
# + get-task-allow); refuses to sign if the profile lacks any of them.
# Run in the GUI (Aqua) session so codesign reaches the login keychain
# identity. No security CLI. Writes ChromeDesktop-device.ipa. Never installs.
set -euo pipefail
export TMPDIR=/tmp TMP=/tmp
SRC=${CHROMIUM_SRC:-$HOME/chromium-build/chromium/src}
OUT=${CHROMIUM_OUT:-$SRC/out/Release-iphoneos-views}
TEAM=${TEAM_ID:-4P2629648N}
WANT_BID=com.davidhope.deskbrowser.chromeviews
UDID=${PHONE_UDID:-00008140-000E44300EE1401C}
IDENTITY=${SIGN_IDENTITY:-$(grep -oE "SIGN_IDENTITY:-[0-9A-F]{40}" $HOME/chromium-build/sign-chrome-ios-device-mem.sh | cut -d- -f2)}
PROFILE=${PROFILE:-$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/7e7e9352-0ddd-456f-bcd5-042e3e8eadac.mobileprovision}
STAGE=$OUT/device-sign
IPA=${SIGNED_IPA:-$OUT/ChromeDesktop-device.ipa}
LOGDIR=$HOME/chromium-build/logs/views-device
ST=$LOGDIR/sign.status
RUNLOG=$LOGDIR/sign.log
mkdir -p "$LOGDIR"; echo RUNNING > "$ST"; : > "$RUNLOG"
{
  echo "$(date '+%F %T %Z') START views sign"
  [ -n "$IDENTITY" ] || { echo "NO_IDENTITY"; exit 6; }
  # Preflight the profile before touching anything.
  python3 - "$PROFILE" "$TEAM.$WANT_BID" "$UDID" <<'PYV'
import subprocess, plistlib, sys, datetime
path, want, udid = sys.argv[1:]
r = subprocess.run(["openssl","smime","-inform","DER","-verify","-noverify"],
                   input=open(path,"rb").read(), capture_output=True, check=True)
pl = plistlib.loads(r.stdout); e = pl.get("Entitlements") or {}
need = ["com.apple.developer.kernel.increased-memory-limit",
        "com.apple.developer.kernel.extended-virtual-addressing", "get-task-allow"]
ok = all(e.get(k) for k in need)
appid = e.get("application-identifier")
has = udid in (pl.get("ProvisionedDevices") or [])
exp = pl.get("ExpirationDate")
live = exp > datetime.datetime.now(exp.tzinfo) if exp else False
jit = "dynamic-codesigning" in e
print("PROFILE", pl.get("Name"), pl.get("UUID"), "exp", exp)
print("APP_ID", appid, "MEM_EVA_GTA", ok, "HAS_PHONE_UDID", has, "LIVE", live)
if appid != want or not ok or not has or not live or jit:
    raise SystemExit("PROFILE_PREFLIGHT_FAILED")
PYV
  rm -rf "$STAGE"; mkdir -p "$STAGE/Payload"
  ditto "$OUT/chrome_views_ios.app" "$STAGE/Payload/chrome_views_ios.app"
  APP=$STAGE/Payload/chrome_views_ios.app
  rm -rf "$APP/PlugIns" "$APP/Extensions"
  find "$APP" -name _CodeSignature -prune -exec rm -rf {} +
  cp "$PROFILE" "$APP/embedded.mobileprovision"
  BID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
  [ "$BID" = "$WANT_BID" ] || { echo "UNEXPECTED_BID $BID"; exit 5; }
  ENT=$STAGE/app.entitlements
  cat > "$ENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$TEAM.$BID</string>
<key>com.apple.developer.team-identifier</key><string>$TEAM</string>
<key>get-task-allow</key><true/>
<key>keychain-access-groups</key><array><string>$TEAM.$BID</string></array>
<key>com.apple.developer.kernel.increased-memory-limit</key><true/>
<key>com.apple.developer.kernel.extended-virtual-addressing</key><true/>
</dict></plist>
EOF
  for fw in "$APP"/Frameworks/*.framework "$APP"/Frameworks/*.dylib; do
    [ -e "$fw" ] || continue
    codesign --force --timestamp=none --sign "$IDENTITY" "$fw"
  done
  codesign --force --timestamp=none --sign "$IDENTITY" --entitlements "$ENT" "$APP"
  codesign --verify --deep --strict "$APP"
  while IFS= read -r b; do
    codesign --verify --strict "$b" || { echo "VERIFY_FAILED $b"; exit 3; }
  done < <(find "$APP" \( -name '*.framework' -o -name '*.dylib' \) -prune -print)
  echo "VERIFY_OK"
  echo "---- signed entitlements ----"
  codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p - || true
  rm -f "$IPA"
  (cd "$STAGE" && /usr/bin/zip -qry "$IPA" Payload)
  sha=$(shasum -a 256 "$IPA" | awk '{print $1}')
  echo "SIGNED_IPA $IPA bytes=$(stat -f %z "$IPA") sha256=$sha"
  echo "$(date '+%F %T %Z') END done rc=0"
} >> "$RUNLOG" 2>&1 && echo done > "$ST" || { echo SIGN_FAILED > "$ST"; exit 2; }
