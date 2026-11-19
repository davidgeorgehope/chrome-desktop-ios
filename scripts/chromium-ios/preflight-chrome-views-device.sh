#!/bin/bash
# Pre-install checks for ChromeDesktop-device.ipa that need no phone.
# Prints PASS/FAIL lines; exit 1 if any FAIL. Never installs anything.
set -uo pipefail
SRC=${CHROMIUM_SRC:-$HOME/chromium-build/chromium/src}
OUT=${CHROMIUM_OUT:-$SRC/out/Release-iphoneos-views}
IPA=${IPA:-$OUT/ChromeDesktop-device.ipa}
UDID=${PHONE_UDID:-00008140-000E44300EE1401C}
fails=0
ok(){ echo "PASS $*"; }; bad(){ echo "FAIL $*"; fails=$((fails+1)); }
chk(){ local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
W=$(mktemp -d /tmp/views-preflight.XXXX); trap 'rm -rf "$W"' EXIT
[ -f "$IPA" ] || { bad "ipa exists $IPA"; exit 1; }
(cd "$W" && unzip -q "$IPA") || bad "ipa unzips"
top=$(cd "$W" && ls); [ "$top" = Payload ] && ok "ipa top level is only Payload/" || bad "ipa top level: $top"
apps=$(ls -d "$W"/Payload/*.app); [ $(echo "$apps" | wc -l) -eq 1 ] && ok "one app in Payload" || bad "apps: $apps"
APP=$apps; PL=$APP/Info.plist
pb(){ /usr/libexec/PlistBuddy -c "Print :$1" "$PL" 2>/dev/null; }
EXE=$APP/$(pb CFBundleExecutable)
[ "$(pb CFBundleIdentifier)" = com.davidhope.deskbrowser.chromeviews ] && ok "bundle id com.davidhope.deskbrowser.chromeviews (Chromium.app is .blink)" || bad "bundle id $(pb CFBundleIdentifier)"
[ "$(pb CFBundleDisplayName)" = "Chrome Desktop" ] && ok "display name Chrome Desktop" || bad "display name $(pb CFBundleDisplayName)"
[ "$(pb CFBundleSupportedPlatforms:0)" = iPhoneOS ] && ok "CFBundleSupportedPlatforms iPhoneOS" || bad "platform $(pb CFBundleSupportedPlatforms:0)"
echo "INFO MinimumOSVersion $(pb MinimumOSVersion) DTSDKName $(pb DTSDKName) DTPlatformName $(pb DTPlatformName)"
[ "$(pb DTPlatformName)" = iphoneos ] && ok "DTPlatformName iphoneos" || bad "DTPlatformName $(pb DTPlatformName)"
pb UILaunchScreen >/dev/null && ok "UILaunchScreen present" || bad "UILaunchScreen missing"
for k in NSMicrophoneUsageDescription NSCameraUsageDescription; do pb $k >/dev/null && ok "$k" || bad "$k missing"; done
pb UIApplicationSceneManifest:UISceneConfigurations >/dev/null && ok "scene manifest" || bad "no scene manifest"
plutil -p "$PL" | grep -q UIWindowSceneSessionRoleExternalDisplay && ok "external display scene role" || bad "no external display scene role"
# Binary
file "$EXE" | grep -q "arm64" && ! lipo -archs "$EXE" | grep -qv '^arm64$' && ok "main executable arm64 only ($(lipo -archs "$EXE"))" || bad "archs $(lipo -archs "$EXE")"
plat=$(vtool -show-build "$EXE" 2>/dev/null | awk '/platform/{print $2; exit}')
[ "$plat" = IOS ] && ok "LC_BUILD_VERSION platform IOS (not simulator)" || bad "build platform $plat"
echo "INFO $(vtool -show-build "$EXE" 2>/dev/null | grep -E 'minos|sdk' | tr -s ' ' | tr '\n' ' ')"
bad_dylibs=$(otool -L "$EXE" | tail -n +2 | awk '{print $1}' | grep -vE '^(/System/Library/|/usr/lib/|@rpath/|@executable_path/)' || true)
[ -z "$bad_dylibs" ] && ok "linkage only system/@rpath" || bad "linkage: $bad_dylibs"
for r in $(otool -L "$EXE" | awk '/@rpath\//{print $1}'); do n=${r#@rpath/}; [ -e "$APP/Frameworks/$n" ] || bad "missing $r"; done
ok "@rpath deps present ($(otool -L "$EXE" | grep -c @rpath))"
for fb in $(find "$APP" -type f \( -perm +111 -o -name '*.dylib' \) ); do
  if file "$fb" | grep -q Mach-O; then a=$(lipo -archs "$fb" 2>/dev/null); [ "$a" = arm64 ] || bad "non-arm64 Mach-O $fb $a"; fi
done; ok "all Mach-O files arm64"
# Resources
for f in chrome_100_percent.pak resources.pak icudtl.dat; do
  n=$(find "$APP" -name "$f" | head -1); [ -n "$n" ] && ok "resource $f ($(stat -f %z "$n") B)" || bad "missing $f"
done
loc=$(find "$APP" -path '*.lproj/*' -name '*.pak' | wc -l | tr -d ' '); [ "$loc" -gt 0 ] && ok "locale paks $loc" || bad "no locale paks"
v8snap=$(find "$APP" -name '*snapshot*.bin' | head -1); [ -n "$v8snap" ] && ok "v8 snapshot $(basename "$v8snap")" || echo "INFO no external v8 snapshot (may be embedded)"
stale=$(find "$APP" \( -name '*.ninja*' -o -name '*.o' -o -name '.DS_Store' -o -name '*.dSYM' -o -name 'PlugIns' -o -name 'Extensions' \) | head)
[ -z "$stale" ] && ok "no build droppings / extensions" || bad "stale: $stale"
# Signing
chk "codesign --verify --deep --strict" codesign --verify --deep --strict "$APP"
codesign -d --entitlements :- "$APP" 2>/dev/null > "$W/ent.plist"
e(){ /usr/libexec/PlistBuddy -c "Print :$1" "$W/ent.plist" 2>/dev/null; }
for k in com.apple.developer.kernel.increased-memory-limit com.apple.developer.kernel.extended-virtual-addressing get-task-allow; do
  [ "$(e $k)" = true ] && ok "signed entitlement $k" || bad "signed entitlement $k"
done
[ "$(e application-identifier)" = 4P2629648N.com.davidhope.deskbrowser.chromeviews ] && ok "application-identifier" || bad "application-identifier $(e application-identifier)"
e dynamic-codesigning >/dev/null && bad "unexpected JIT entitlement dynamic-codesigning" || ok "no JIT entitlement (jitless)"
openssl smime -inform der -verify -noverify -in "$APP/embedded.mobileprovision" 2>/dev/null > "$W/prof.plist"
pp(){ /usr/libexec/PlistBuddy -c "Print :$1" "$W/prof.plist" 2>/dev/null; }
[ "$(pp Entitlements:application-identifier)" = "$(e application-identifier)" ] && ok "profile app id matches signature" || bad "profile app id $(pp Entitlements:application-identifier)"
plutil -p "$W/prof.plist" | grep -q "$UDID" && ok "profile includes phone UDID" || bad "profile lacks phone UDID"
for k in com.apple.developer.kernel.increased-memory-limit com.apple.developer.kernel.extended-virtual-addressing get-task-allow; do
  [ "$(pp Entitlements:$k)" = true ] && ok "profile grants $k" || bad "profile lacks $k"
done
echo "INFO profile $(pp Name) exp $(pp ExpirationDate)"
# Cert in profile matches the signing cert
codesign -d --extract-certificates="$W/c" "$APP" 2>/dev/null
lc=$(openssl x509 -inform der -in "$W/c0" -noout -fingerprint -sha1 2>/dev/null | cut -d= -f2 | tr -d :)
python3 - "$W/prof.plist" "$lc" <<'PY' && ok "signing cert is in the profile" || bad "signing cert not in profile"
import plistlib,sys,hashlib
pl=plistlib.load(open(sys.argv[1],'rb'))
fps={hashlib.sha1(c).hexdigest().upper() for c in pl.get('DeveloperCertificates',[])}
sys.exit(0 if sys.argv[2] in fps else 1)
PY
# Jitless/single-process defaults and heap cap in the source we built
grep -q 'kJitless\|"jitless"\|js-flags=--jitless\|--jitless' "$SRC/chrome/browser/ui/views/ios/chrome_views_ios_main.mm" && ok "source forces jitless" || bad "jitless flag not found in chrome_views_ios_main.mm"
grep -q 'kSingleProcess\|single-process' "$SRC/chrome/browser/ui/views/ios/chrome_views_ios_main.mm" && ok "source forces single-process" || bad "single-process not found"
grep -q 'max-old-space-size' "$SRC/content/app/content_main.cc" && ok "device heap cap (--max-old-space-size) in content_main.cc" || bad "heap cap missing"
LC_ALL=C grep -aq 'max-old-space-size=' "$EXE" && ok "heap cap string in binary" || bad "heap cap string not in binary"
# Old device app untouched
if [ -f "$HOME/chromium-build/logs/views-device/device-args.md5" ]; then
  [ "$(md5 -q "$SRC/out/Release-iphoneos/args.gn")" = "$(cat "$HOME/chromium-build/logs/views-device/device-args.md5")" ] && ok "out/Release-iphoneos/args.gn unchanged" || bad "out/Release-iphoneos/args.gn changed"
fi
grep -q enable_ios_desktop_views "$SRC/out/Release-iphoneos/args.gn" && bad "old device args mention enable_ios_desktop_views" || ok "old device args keep enable_ios_desktop_views default (off)"
echo "INFO ipa bytes=$(stat -f %z "$IPA") sha256=$(shasum -a 256 "$IPA" | awk '{print $1}')"
echo "RESULT fails=$fails"; [ $fails -eq 0 ]
