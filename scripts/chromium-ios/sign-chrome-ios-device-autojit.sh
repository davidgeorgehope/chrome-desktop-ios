#!/bin/bash
# Sign the device Chrome with the explicit blink profile (memory
# entitlements) and embed the built-in StikJIT helper. StikJIT.framework
# is rsynced without Headers/PrivateHeaders/Modules so a later copy
# cannot strip them after signing (crate 0004 / 0xe8008017).
# Cleans stale helper/framework products first.
# Override the output path with SIGNED_IPA.
set -euo pipefail
export TMPDIR=/tmp
export TMP=/tmp
SRC=${CHROMIUM_SRC:-$HOME/chromium-build/chromium/src}
OUT=${CHROMIUM_OUT:-$SRC/out/Release-iphoneos}
TEAM=${TEAM_ID:-4P2629648N}
IDENTITY=${SIGN_IDENTITY:-25CEDB906C81B51A388B7E41B7CC0F2F27E7502F}
PROFILE=${PROFILE:-$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/90f5f0e8-a912-4f5f-9d53-31f55271ef63.mobileprovision}
HELPER_SRC=${HELPER_APPEX:-$HOME/chromium-build/jit-helper/DeskBrowserJITHelper.appex}
STIKJIT_FW=${STIKJIT_FW:-$HOME/chromium-build/Frameworks/StikJIT.xcframework/ios-arm64/StikJIT.framework}
STAGE=$OUT/device-sign-autojit
IPA=${SIGNED_IPA:-$OUT/Chromium-device-autojit.ipa}
LOGDIR=$HOME/chromium-build/logs
JOB=${JOB:-chromium-ios-chrome-device-autojit}
ST=$LOGDIR/chrome-device-autojit-sign.status
RUNLOG=$LOGDIR/chrome-device-autojit-sign.current.log
HIST=$LOGDIR/chrome-device-autojit-sign.log
DETAIL=/tmp/chrome-device-autojit-sign-detail.txt
mkdir -p "$LOGDIR"
echo RUNNING > "$ST"
: > "$RUNLOG"

{
  echo "$(date '+%F %T %Z') START autojit sign"
  echo "PROFILE=$PROFILE"
  echo "HELPER_SRC=$HELPER_SRC"
  [ -d "$HELPER_SRC" ] || { echo "missing helper appex: $HELPER_SRC"; exit 2; }
  [ -d "$STIKJIT_FW" ] || { echo "missing StikJIT.framework: $STIKJIT_FW"; exit 2; }

  rm -rf "$STAGE"; mkdir -p "$STAGE/Payload"
  ditto "$OUT/Chromium.app" "$STAGE/Payload/Chromium.app"
  APP=$STAGE/Payload/Chromium.app

  # Drop BrowserEngineKit child-process Extensions; keep only our JIT helper.
  rm -rf "$APP/PlugIns" "$APP/Extensions" "$APP/_CodeSignature"
  find "$APP" -name _CodeSignature -prune -exec rm -rf {} +

  mkdir -p "$APP/PlugIns"
  # Clean copy of the unsigned helper, then embed StikJIT without headers.
  ditto "$HELPER_SRC" "$APP/PlugIns/DeskBrowserJITHelper.appex"
  HELPER="$APP/PlugIns/DeskBrowserJITHelper.appex"
  rm -rf "$HELPER/Frameworks/StikJIT.framework" "$HELPER/_CodeSignature"
  mkdir -p "$HELPER/Frameworks"
  rsync -a --delete --exclude Headers --exclude PrivateHeaders --exclude Modules \
    "$STIKJIT_FW" "$HELPER/Frameworks/"
  rm -rf "$HELPER/Frameworks/StikJIT.framework/Headers" \
         "$HELPER/Frameworks/StikJIT.framework/PrivateHeaders" \
         "$HELPER/Frameworks/StikJIT.framework/Modules" \
         "$HELPER/Frameworks/StikJIT.framework/_CodeSignature"

  cp "$PROFILE" "$APP/embedded.mobileprovision"
  # Helper uses the team wildcard (get-task-allow only). The explicit
  # blink profile is bound to the main App ID and must not be embedded here.
  HELPER_PROFILE=${HELPER_PROFILE:-$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/4d14b35d-df44-468b-89a4-dac7d68e4362.mobileprovision}
  cp "$HELPER_PROFILE" "$HELPER/embedded.mobileprovision"
  BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
  HELPER_BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HELPER/Info.plist")

  # Main-app Info.plist: query LocalDevVPN, describe local-network use,
  # accept the existing chromium URL scheme as the VPN return.
  python3 - "$APP/Info.plist" <<'PYPL'
import plistlib, sys
from pathlib import Path
path = Path(sys.argv[1])
pl = plistlib.loads(path.read_bytes())
schemes = list(pl.get("LSApplicationQueriesSchemes") or [])
if "localdevvpn" not in schemes:
    schemes.append("localdevvpn")
pl["LSApplicationQueriesSchemes"] = schemes
pl["NSLocalNetworkUsageDescription"] = (
    "Chrome uses LocalDevVPN on this iPhone so JIT can start when you open the app."
)
# Keep the original format when we can; binary is always accepted by iOS.
fmt = plistlib.FMT_BINARY if path.read_bytes().startswith(b"bplist") else plistlib.FMT_XML
plistlib.dump(pl, path.open("wb"), fmt=fmt)
print("Info.plist localdevvpn + local-network description set")
PYPL

  ENT=$STAGE/app.entitlements
  cat > "$ENT" <<PLIST
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
PLIST
  HELPER_ENT=$STAGE/helper.entitlements
  cat > "$HELPER_ENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$TEAM.$HELPER_BID</string>
<key>com.apple.developer.team-identifier</key><string>$TEAM</string>
<key>get-task-allow</key><true/>
</dict></plist>
PLIST

  # Sign inside-out: StikJIT, other frameworks, helper, app.
  codesign --force --timestamp=none --sign "$IDENTITY" "$HELPER/Frameworks/StikJIT.framework"
  for fw in "$APP"/Frameworks/*.framework "$APP"/Frameworks/*.dylib; do
    [ -e "$fw" ] || continue
    codesign --force --timestamp=none --sign "$IDENTITY" "$fw"
  done
  codesign --force --timestamp=none --sign "$IDENTITY" --entitlements "$HELPER_ENT" "$HELPER"
  codesign --force --timestamp=none --sign "$IDENTITY" --entitlements "$ENT" "$APP"

  echo "---- strict verify (every nested bundle) ----"
  fail=0
  while IFS= read -r b; do
    echo "verify $b"
    if ! codesign --verify --strict "$b"; then
      echo "VERIFY_FAILED $b"
      fail=1
    fi
  done < <(find "$APP" \( -name '*.app' -o -name '*.framework' -o -name '*.appex' -o -name '*.dylib' \))
  [ "$fail" -eq 0 ] || exit 3

  echo "---- signed app entitlements ----"
  codesign -d --entitlements :- "$APP" 2>/dev/null | head -60
  echo "---- helper entitlements ----"
  codesign -d --entitlements :- "$HELPER" 2>/dev/null | head -40
  echo "---- MinimumOSVersion ----"
  /usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP/Info.plist" || true
  echo "---- PlugIns ----"
  ls -d "$APP/PlugIns"/* "$APP/Extensions" 2>/dev/null || echo "plugins listed above"
  # StikJIT must not contain Headers/Modules
  if [ -d "$HELPER/Frameworks/StikJIT.framework/Headers" ] || [ -d "$HELPER/Frameworks/StikJIT.framework/Modules" ]; then
    echo "StikJIT still has Headers or Modules; aborting"
    exit 3
  fi

  rm -f "$IPA"
  (cd "$STAGE" && /usr/bin/zip -qry "$IPA" Payload)
  ls -l "$IPA"
  python3 - "$APP/embedded.mobileprovision" <<'PYV'
import subprocess, plistlib, sys
raw=open(sys.argv[1],"rb").read()
r=subprocess.run(["openssl","smime","-inform","DER","-verify","-noverify"], input=raw, capture_output=True, check=True)
pl=plistlib.loads(r.stdout)
ents=pl.get("Entitlements") or {}
udid="00008140-000E44300EE1401C"
keys=set(ents)
need=["com.apple.developer.kernel.increased-memory-limit","com.apple.developer.kernel.extended-virtual-addressing","get-task-allow"]
ok=all(k in keys and ents[k] for k in need)
has=udid in (pl.get("ProvisionedDevices") or [])
print("PROFILE_NAME", pl.get("Name"))
print("PROFILE_UUID", pl.get("UUID"))
print("APP_ID", ents.get("application-identifier"))
print("MEM_EVA_GETTASK", ok)
print("HAS_PHONE_UDID", has)
print("EXPIRATION", pl.get("ExpirationDate"))
if not ok or not has:
    raise SystemExit(4)
PYV
  sha=$(shasum -a 256 "$IPA" | awk '{print $1}')
  echo "SIGNED_IPA $IPA bundle=$BID helper=$HELPER_BID sha256=$sha"
  echo "$(date '+%F %T %Z') END done rc=0"
} 2>&1 | tee -a "$RUNLOG" "$HIST"

if grep -q "SIGNED_IPA " "$RUNLOG" && grep -q "END done rc=0" "$RUNLOG"; then
  echo done > "$ST"
  tail -40 "$RUNLOG" | sed 's/\x1b\[[0-9;]*[mK]//g' > "$DETAIL"
  "$HOME/chromium-build/notify-poke.sh" "$JOB" done 0 "$DETAIL" || true
  exit 0
fi
echo SIGN_FAILED > "$ST"
python3 - "$RUNLOG" "$DETAIL" <<'PYE'
import re, sys
src, dest = sys.argv[1], sys.argv[2]
ansi = re.compile(r"\x1b\[[0-9;]*[mK]")
text = open(src, errors="replace").read()
lines = [ansi.sub("", ln).rstrip() for ln in text.splitlines()]
interesting = [ln for ln in lines if re.search(r"error:|failed|VERIFY|errSec|SIGNED|rc=", ln, re.I)]
out = interesting[-30:] if interesting else lines[-30:]
open(dest,"w",encoding="utf-8").write("\n".join(out)+("\n" if out else ""))
PYE
"$HOME/chromium-build/notify-poke.sh" "$JOB" SIGN_FAILED 2 "$DETAIL" || true
exit 2
