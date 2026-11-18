#!/bin/bash
# Re-sign the already-built device Chrome with the explicit
# com.davidhope.deskbrowser.blink profile (increased-memory-limit +
# extended-virtual-addressing). Writes Chromium-device-jit-mem.ipa so the
# wildcard-signed Chromium-device.ipa is left alone. No security CLI.
set -euo pipefail
export TMPDIR=/tmp
export TMP=/tmp
SRC=${CHROMIUM_SRC:-$HOME/chromium-build/chromium/src}
OUT=${CHROMIUM_OUT:-$SRC/out/Release-iphoneos}
TEAM=${TEAM_ID:-4P2629648N}
IDENTITY=${SIGN_IDENTITY:-25CEDB906C81B51A388B7E41B7CC0F2F27E7502F}
PROFILE=${PROFILE:-$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/90f5f0e8-a912-4f5f-9d53-31f55271ef63.mobileprovision}
STAGE=$OUT/device-sign-mem
IPA=${SIGNED_IPA:-$OUT/Chromium-device-jit-mem.ipa}
LOGDIR=$HOME/chromium-build/logs
JOB=${JOB:-chromium-ios-chrome-device-jit-mem}
ST=$LOGDIR/chrome-device-jit-mem-sign.status
RUNLOG=$LOGDIR/chrome-device-jit-mem-sign.current.log
HIST=$LOGDIR/chrome-device-jit-mem-sign.log
DETAIL=/tmp/chrome-device-jit-mem-sign-detail.txt
mkdir -p "$LOGDIR"
echo RUNNING > "$ST"
: > "$RUNLOG"

{
  echo "$(date '+%F %T %Z') START mem re-sign"
  echo "PROFILE=$PROFILE"
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
  done < <(find "$APP" \( -name '*.framework' -o -name '*.appex' -o -name '*.dylib' \) -prune -print)
  echo "---- signed entitlements ----"
  codesign -d --entitlements :- "$APP" 2>/dev/null | head -60
  echo "---- MinimumOSVersion ----"
  /usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP/Info.plist" || true
  echo "---- PlugIns/Extensions ----"
  ls -d "$APP/PlugIns" "$APP/Extensions" 2>/dev/null || echo "none"
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
  echo "SIGNED_IPA $IPA bundle=$BID sha256=$sha"
  echo "$(date '+%F %T %Z') END done rc=0"
} 2>&1 | tee -a "$RUNLOG" "$HIST"

# Detect failure if the last END line is missing or VERIFY failed
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
