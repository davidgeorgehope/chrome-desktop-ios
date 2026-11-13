# Overridable Designed-for-iPad bundle identifiers

The official product ID `com.imxieyi.Kernarium` cannot be registered to a
personal team. Automatic signing then falls back to the wildcard iOS team
profile, which lacks Extended Virtual Addressing and Increased Memory Limit
and may not include this Mac.

This change keeps the official IDs as the default and lets a checkout override
them in the already-ignored `GuestHost/Config/Signing.local.xcconfig` (see the
updated example), or with `KERNARIUM_BUNDLE_IDENTIFIER` in the environment for
`Kernarium/scripts/run-ios-mac.sh`.

Apply `bundle-id.patch` in the Kernarium tree, then in
`Kernarium/Kernarium.xcodeproj/project.pbxproj` point each target's
`PRODUCT_BUNDLE_IDENTIFIER` at the xcconfig variable (both configurations):

```
PRODUCT_BUNDLE_IDENTIFIER = "$(KERNARIUM_BUNDLE_IDENTIFIER)";
PRODUCT_BUNDLE_IDENTIFIER = "$(KERNARIUM_TESTS_BUNDLE_IDENTIFIER)";
PRODUCT_BUNDLE_IDENTIFIER = "$(KERNARIUM_UITESTS_BUNDLE_IDENTIFIER)";
PRODUCT_BUNDLE_IDENTIFIER = "$(KERNARIUM_AUTOMATION_BUNDLE_IDENTIFIER)";
```

A safe in-place rewrite, longer names first:

```sh
python3 - <<'PY'
from pathlib import Path
p = Path("Kernarium/Kernarium.xcodeproj/project.pbxproj")
t = p.read_text()
repls = [
    ("com.imxieyi.KernariumAutomation", "$(KERNARIUM_AUTOMATION_BUNDLE_IDENTIFIER)"),
    ("com.imxieyi.KernariumUITests", "$(KERNARIUM_UITESTS_BUNDLE_IDENTIFIER)"),
    ("com.imxieyi.KernariumTests", "$(KERNARIUM_TESTS_BUNDLE_IDENTIFIER)"),
    ("com.imxieyi.Kernarium", "$(KERNARIUM_BUNDLE_IDENTIFIER)"),
]
for old, new in repls:
    needle = f"PRODUCT_BUNDLE_IDENTIFIER = {old};"
    want = f'PRODUCT_BUNDLE_IDENTIFIER = "{new}";'
    count = t.count(needle)
    if count == 0:
        raise SystemExit(f"no {old}")
    t = t.replace(needle, want)
    print(old, "->", count)
p.write_text(t)
PY
```

Do not commit `Signing.local.xcconfig`. On the bakeoff mini that file sets
team `4P2629648N` (the same team Voxl Pocket uses) and
`com.davidhope.kernarium` / `.tests` / `.uitests` / `.automation`. Xcode
automatic signing then registers the App ID, issues an iOS Team Provisioning
Profile that includes the kernel entitlements, `get-task-allow`, and this Mac
(`00006020-0009715A216B401E`). `com.apple.security.cs.allow-jit` stays in the
source entitlements but is stripped at sign time: it is not in the iOS
profile, and forcing it back yields `0xe8008015`.

Codesign of the iphoneos product must run in the Aqua/gui session (SSH
`codesign` fails with `errSecInternalComponent`). Do not use the Keychain
`security` CLI for that. Launch with `run-ios-mac.sh` and
`xcodebuild test` to destination `platform=macOS,variant=Designed for iPad`
only. Do not install on a paired iPhone.
