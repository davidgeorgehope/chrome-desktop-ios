#!/bin/bash
# Mint an explicit App ID + profile for com.davidhope.deskbrowser.blink
# via Xcode automatic signing (Aqua session). No secrets; no security CLI.
set -u
set -o pipefail
export TMPDIR=/tmp
export TMP=/tmp
ROOT="$HOME/chromium-build"
STUB="$ROOT/blink-appid-stub"
LOGDIR="$ROOT/logs"
JOB=chromium-ios-blink-appid-stub
ST="$LOGDIR/blink-appid-stub.status"
RUNLOG="$LOGDIR/blink-appid-stub.current.log"
HIST="$LOGDIR/blink-appid-stub.log"
DETAIL="/tmp/blink-appid-stub-detail.txt"
STATUS="$STUB/profile-status.txt"
UDID="00008140-000E44300EE1401C"
TEAM="4P2629648N"
BID="com.davidhope.deskbrowser.blink"
mkdir -p "$LOGDIR"
echo RUNNING > "$ST"
: > "$RUNLOG"
{
  echo "$(date '+%F %T %Z') START blink-appid-stub automatic signing"
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
  cd "$STUB"
  xcodebuild -project BlinkAppIDStub.xcodeproj -scheme BlinkAppIDStub \
    -configuration Debug \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -allowProvisioningUpdates \
    -derivedDataPath "$STUB/DerivedData" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM" \
    PRODUCT_BUNDLE_IDENTIFIER="$BID" \
    build
  echo "$(date '+%F %T %Z') XCODEBUILD rc=$?"
} 2>&1 | tee -a "$RUNLOG" "$HIST"
rc=$(tail -40 "$RUNLOG" | sed -n 's/.*XCODEBUILD rc=\([0-9][0-9]*\).*/\1/p' | tail -1)
if [ -z "${rc:-}" ]; then rc=1; fi

extract_errors() {
  /usr/bin/python3 - "$RUNLOG" "$DETAIL" <<'PYE'
import re, sys
src, dest = sys.argv[1], sys.argv[2]
ansi = re.compile(r"\x1b\[[0-9;]*[mK]")
text = open(src, errors="replace").read()
lines = [ansi.sub('', ln).rstrip() for ln in text.splitlines()]
interesting = [ln for ln in lines if re.search(
    r"error:|failed|FAILED|Provisioning|CodeSign|No profiles|XCODEBUILD rc=",
    ln, re.I)]
out = interesting[-30:] if interesting else lines[-30:]
open(dest, "w", encoding="utf-8").write("\n".join(out) + ("\n" if out else ""))
print("detail lines:", len(out))
PYE
}

python3 - "$STATUS" "$TEAM" "$BID" "$UDID" <<'PYS'
import os, sys, subprocess, plistlib, pathlib
status, team, bid, udid = sys.argv[1:]
want = f"{team}.{bid}"
profdir = pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
found = []
for f in sorted(profdir.glob("*.mobileprovision")):
    r = subprocess.run(["openssl","smime","-inform","DER","-verify","-noverify"],
                       input=f.read_bytes(), capture_output=True)
    if r.returncode != 0:
        continue
    pl = plistlib.loads(r.stdout)
    ents = pl.get("Entitlements") or {}
    appid = ents.get("application-identifier")
    if appid != want:
        continue
    keys = set(ents.keys())
    mem = "com.apple.developer.kernel.increased-memory-limit" in keys
    eva = "com.apple.developer.kernel.extended-virtual-addressing" in keys
    devices = pl.get("ProvisionedDevices") or []
    has = udid in devices
    found.append((f, pl.get("UUID"), pl.get("Name"), mem, eva, has, pl.get("ExpirationDate")))
lines = []
if not found:
    lines.append("PROFILE_MISSING")
else:
    f, uuid, name, mem, eva, has, exp = sorted(found, key=lambda t: t[0].stat().st_mtime)[-1]
    lines.append(f"PROFILE_PATH={f}")
    lines.append(f"PROFILE_UUID={uuid}")
    lines.append(f"PROFILE_NAME={name}")
    lines.append(f"APP_ID={want}")
    lines.append(f"INCREASED_MEMORY_LIMIT={mem}")
    lines.append(f"EXTENDED_VIRTUAL_ADDRESSING={eva}")
    lines.append(f"HAS_PHONE_UDID={has}")
    lines.append(f"EXPIRATION={exp}")
    print(f"found uuid={uuid} mem={mem} eva={eva} udid={has}")
pathlib.Path(status).write_text("\n".join(lines) + "\n")
PYS

ok_profile=0
if grep -q "INCREASED_MEMORY_LIMIT=True" "$STATUS" \
   && grep -q "EXTENDED_VIRTUAL_ADDRESSING=True" "$STATUS" \
   && grep -q "HAS_PHONE_UDID=True" "$STATUS"; then
  ok_profile=1
fi

if [ "$rc" -eq 0 ] && [ "$ok_profile" -eq 1 ]; then
  echo done > "$ST"
  echo "$(date '+%F %T %Z') END done rc=0" | tee -a "$RUNLOG" "$HIST"
  { echo "xcodebuild ok"; cat "$STATUS"; } > "$DETAIL"
  "$ROOT/notify-poke.sh" "$JOB" done 0 "$DETAIL" || true
  exit 0
fi

echo BUILD_FAILED > "$ST"
echo "$(date '+%F %T %Z') END BUILD_FAILED rc=$rc profile_ok=$ok_profile" | tee -a "$RUNLOG" "$HIST"
extract_errors
cat "$STATUS" >> "$DETAIL" 2>/dev/null || true
"$ROOT/notify-poke.sh" "$JOB" BUILD_FAILED "$rc" "$DETAIL" || true
exit "$rc"
