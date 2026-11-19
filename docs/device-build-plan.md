# Device build plan: desktop Views on the monitor, iOS Chrome on the phone

Status 2026-11-19 1:20 PM ET. Planning only: nothing has been built for or
installed on a phone, and `out/Release-iphoneos/args.gn` keeps
`enable_ios_desktop_views` off.

## Goal

- No monitor: the phone runs the existing jitless iOS Chromium (`//ios/chrome`
  UIKit + Blink via `ios/web/content`) exactly as today.
- Monitor attached: the monitor shows the real desktop `BrowserView`
  (tab strip, toolbar, omnibox, Blink WebContents) and the phone becomes the
  trackpad/keyboard (patch 0119).

## Constraint that shapes the plan

Both browsers embed `//content`, and content can be initialized only once per
process (one `ContentMainRunner`, one `BrowserMainLoop`, one set of
`BrowserThread`s). `//ios/chrome` and `//chrome` (`BrowserProcessImpl`,
profiles, prefs, keyed services) are separate embedders with separate profile
stores. They cannot both run in one process. A hot-plug switch inside one
running process is therefore not a first-step option.

## Phases

### Phase A: two apps (recommended first device step)

- Keep `Chromium.app` (`//ios/chrome`) unchanged: same out dir, same args,
  same bundle id, flag off.
- Build the Views app (`//chrome/browser/ui/views/ios:chrome_views_ios`,
  bundle `com.davidhope.deskbrowser.chromeviews`) in a **new** out dir,
  `out/Release-iphoneos-views`, with `target_environment = "device"`,
  `enable_ios_desktop_views = true`, `use_blink = true`, `is_debug = false`.
  The flag is on only in that separate dir; the existing device `args.gn` is
  not touched.
- Runtime flags are already forced in `chrome_views_ios_main.mm`:
  `--single-process`, `--in-process-gpu`, `--js-flags=--jitless`. No JIT
  entitlement is needed or requested.
- The user opens the Views app when docked. Its phone scene is the trackpad;
  with no external scene it should show a "connect a display" placeholder
  rather than a phone-sized desktop window (TODO, small).

### Phase B: one bundle, mode chosen at launch

- One app containing both embedders' code, with `main` choosing the embedder
  before content starts: external `UIScreen`/scene present at launch → Views
  embedder; otherwise → `//ios/chrome`.
- On hot-plug, show a "Relaunch in desktop mode" (or phone mode) prompt that
  saves state and exits; iOS cannot relaunch an app itself, so the user taps
  the icon. Shared data between modes (bookmarks, history, passwords) needs
  sync or a migration step because the profile formats differ.
- Binary size roughly doubles (two browser UIs plus shared content/Blink);
  measure against the App Store/sideload limit before committing to this.

### Phase C (research): one process, hot-plug without relaunch

Only if B's relaunch is unacceptable. It would mean making `//ios/chrome` a
UI over the `//chrome` browser process (or the reverse). That is a large
project and is out of scope for the device milestone.

## Device-specific work before a first install (Phase A)

1. **GN/compile for arm64 device.** The device toolchain hits code that the
   simulator does not, e.g. `TARGET_OS_SIMULATOR` branches in IOSurface and
   Metal, and BrowserEngineKit availability. Expect a short port list.
2. **Compositor on device.** 0111 attaches the compositor CALayer directly
   (single-process); IOSurface-backed CALayer contents should work on device.
   Confirm on device that the Metal/ANGLE path works, not just SwiftShader.
3. **External display on hardware.** The sim TVOut scene is the
   `UIWindowSceneSessionRoleExternalDisplay` role. On a real cable, check
   that the external scene connects (not mirroring), 1080p/4K scale, and the
   reconnect path (`/tmp/site.sh` re-plug logic is sim-only).
4. **Memory.** Single process: browser + renderer + GPU in one app.
   Keep `com.apple.developer.kernel.increased-memory-limit` and the heap cap
   (standing rule); watch jetsam with YouTube 1080p.
5. **Audio/mic/camera.** 0122 uses Playback + MixWithOthers, upgrading to
   PlayAndRecord on first input stream; 0123 adds the usage strings. On
   device the TCC prompt is real: verify the prompt appears on the phone
   scene, not on the external scene.
6. **Signing.** `ios_enable_code_signing = false` in GN; sign in the existing
   packaging step with the same entitlements as the current device IPA
   (EVA, increased-memory-limit, get-task-allow). Do not add a JIT
   entitlement.

## Validation gates (each must pass before the next step)

| Gate | Check | Where |
| --- | --- | --- |
| G1 | Simulator desktop-mode checklist all PASS on the current patch set | docs/desktop-mode-verification.md |
| G2 | Simulator interaction: omnibox, scroll, video+audio, mic recording, context/app menus open, act and close | docs/views-ios-verification-2026-11-19.md |
| G3 | `out/Release-iphoneos-views` compiles and links for arm64 device | mini |
| G4 | `codesign -d --entitlements` shows only the agreed entitlements; Info.plist has the mic/camera strings; no JIT entitlement | mini, read-only |
| G5 | `out/Release-iphoneos/args.gn` still has the flag off and `Chromium.app` still builds unchanged | mini |
| G6 | David's explicit go-ahead before anything is installed on his phone | David |

Only after G6: install the Views app, verify on a real monitor here first
(standing rule: verify before asking David to test), then hand off.

## Not doing now

- No device build or install today.
- No change to `out/Release-iphoneos/args.gn`.
- No merging of the two embedders (Phase B/C) until Phase A runs on hardware.
