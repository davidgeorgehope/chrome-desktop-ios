# crate-ios local bakeoff patches

These are local fixes for the linux-ios-fast crate-ios bakeoff. They are a
patch set, not a vendored copy of crate-ios (MPL-2.0). Do not push the
scratch clone at `linux-ios-bakeoff/scratch/crate-ios` to upstream.

Base: crate-ios tip `7c351b0` (v0.1.3). Apply `0001-local-bakeoff-fixes.patch`
on a clean checkout, then add `Tests/CrateD4Probe/StayAliveTests.swift`.

What the patch carries:

- `RootView` forwards `MachineStore`, `JITSession`, and `MachineRunner` into
  the `fullScreenCover` `MachineScreen`. Designed-for-iPad / iOS 26 can drop
  those `@Observable` environment values otherwise, and Start does nothing.
- Bakeoff-only `--start`: once JIT is on, open and boot the first machine.
  `CRATE_CODE_REGION_MB` can override the code-region size at launch.
- `CRATE_HAS_IOS27_SDK` guards around iOS 27 hinge / toolbar APIs so the
  tree builds with an older SDK.
- Bundle IDs `com.davidhope.crate` / `.jithelper` / `.d4probe`. Upstream
  `com.amendez.crate` cannot be registered to team `4P2629648N` ("not
  available"). The wildcard `iOS Team Provisioning Profile: *` does not
  include `increased-memory-limit` or `extended-virtual-addressing`. An
  explicit App ID profile for `com.davidhope.crate` does (same as Henge,
  LinuxRunner, and Kernarium on this team).
- `Resources/Crate.entitlements` (and the copy here) has `get-task-allow`
  plus both memory entitlements. Do not set `CODE_SIGN_ENTITLEMENTS`
  globally: the JIT helper must not inherit the kernel entitlements.
  Build with `DEVELOPMENT_TEAM=4P2629648N` and `-allowProvisioningUpdates`.

On a 16 Pro (8 GB), the process limit without those entitlements was
~3.54 GB. With them, crate.log reports 6 GiB (6,442,450,944 bytes). A
4 GB guest plus 1024 MB of resident JIT leaves about 1 GiB of headroom
under that cap. If jetsam kills the app, step the guest down to 3.5 GB.

The JIT helper is built-in StikJIT and needs a pairing file at
`Documents/StikJIT/pairingFile.plist` plus a LocalDevVPN tunnel to
`10.7.0.1:49152`. Never commit or print a pairing file.

`CrateD4Probe` is a hosted stay-alive test so an lldb waiter can bless
`brk #0x69` pages on Designed-for-iPad. On a device, built-in StikJIT
does that job instead.


## 0002: external display, hardware mouse, phone trackpad

`0002-external-display-mouse-trackpad.patch` applies on clean `7c351b0` and
**supersedes** `0001-local-bakeoff-fixes.patch` (it includes those bakeoff
fixes plus the display/input work). New and modified sources stay MPL-2.0.
Do not copy this into Kernarium. Henge (GPL-2.0) was used as an approach
only; no Henge files are in the patch.

What 0002 adds on top of 0001:

- Info.plist scene manifest for
  `UIWindowSceneSessionRoleExternalDisplayNonInteractive` →
  `$(PRODUCT_MODULE_NAME).ExternalDisplaySceneDelegate`, with
  `UIApplicationSupportsMultipleScenes` left false (without that entry,
  iOS 26 only mirrors and the app hears nothing).
- `UIApplicationSupportsIndirectInputEvents`. GameController is linked.
- Full-screen external scene at the monitor's size (`fitPixels`, cap raised
  from 2560 to 4095 so 3840×2160 fits). Unplug clears `locksToExternal` so
  the guest falls back to the phone view's size.
- Hardware mouse (`GCMouse`) with pointer lock requested via a real
  `UIViewController` (`prefersPointerLocked`). Buttons and wheel mapped
  through the existing absolute tablet API (crate has no relative mouse).
  An iPhone never actually locks the system pointer; motion still arrives.
- Phone trackpad while the desktop is on the monitor: move, tap, two-finger
  right click, hold-to-drag, two-finger scroll.
- `GuestKeyboard` keeps a first responder for a hardware keyboard in
  trackpad mode (the external scene is NonInteractive, so keys stay on the
  phone scene).
- Guest mode list includes 1920×1080 and 3840×2160, always landscape, so
  Chromium/Firefox render desktop sites.

See `README-0002.md` and the NOTES entry from 14 Nov 2026, 8:05–8:20 PM ET.


## 0003: external display fills the monitor; per-VM resolution setting

`0003-external-display-fill-and-resolution-setting.patch` applies on top of
`0002` (clean `7c351b0` + 0002 + 0003 reproduces the scratch tree exactly).
MPL-2.0; no Henge code.

Root cause of "left third black, desktop cut off on the right" on a monitor:
`showDesktop` gave the picture view a frame of the monitor's size and
flexible autoresizing, then put it in the host controller's view *before*
that view was in the window. A fresh view controller's view starts at the
iPhone's own screen size (402×874 pt), so the margins went negative; when
the window grew the host to 1920×1080 the picture view became 3438×1286,
and the aspect-fit picture inside it started at x≈576 (30% black on the
left, ~36% for a 1280×800 guest), with the right and bottom off-screen.
Reproduced in the Simulator before the fix
(`notes/crate-ios-shots/ext-before-1920x1080.png`, logged
`view 3438x1286 in super 1920x1080, picture x 575.9`).

What 0003 changes:

- Picture view pinned to the host's edges with constraints; window frame set
  to the scene's bounds.
- The layer is `bounds`-sized with `contentsGravity = .resizeAspect`, so a
  guest that doesn't match the monitor's shape is centred with equal bars
  (never one side).
- The guest size offered to the VM comes from the scene's bounds × scale
  (what is actually drawn); `currentMode` is only a fallback. Over 4095 a
  side both sides shrink together, keeping the monitor's shape.
- `crate.log` now records currentMode, preferredMode, availableModes,
  scene points/scale, nativeBounds/nativeScale, overscanCompensation and
  insets, plus the picture view's frame vs the window and the guest size.
- Edit Settings… is no longer greyed out (upstream enabled it only on
  devices with a hinge, since its only setting was iPhone Duo's). The sheet
  adds Display → Resolution: **Match Screen** (default; follows the phone or
  the monitor's native mode through virtio-gpu preferred modes) or a fixed
  size (1280×800 … 3840×2160). Locked while that VM runs. The card shows
  "Fits screen" or the fixed size.
- Debug-only `CRATE_EXTERNAL_TEST_PATTERN=1|WxH` draws a test card on the
  monitor through the same view a VM uses (the Simulator has no JIT).
  Test script: `scripts/crate-ios/ext-display-simtest.sh`.

Simulator results (Peek iPhone 17, iOS 26.5, external display via
`simctl io … screenConfig geometry`): 1280×720, 1920×1080, 1920×1200,
2560×1440, 3440×1440, 3840×2160 all fill edge to edge (content bbox = full
frame). Fixed 1280×800 guest on 1920×1080: centred, 96 px bars each side.
