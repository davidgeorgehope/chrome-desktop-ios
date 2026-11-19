# Chrome Desktop for iPhone

Real desktop Chrome, running natively on an iPhone, full screen on an external monitor, with the phone as the trackpad.

## What it is

This is Chromium's actual desktop browser: the Blink engine plus the desktop
Views UI (tab strip, toolbar, omnibox, app menu, right-click menus). It runs on
the phone itself and draws full screen on a monitor plugged into it. The
phone's screen turns into a trackpad.

It is not remote desktop, not a WKWebView wrapper, and not a mobile site.
Sites get full desktop mode:

- Mac user agent, `Sec-CH-UA-Mobile: ?0`, `navigator.userAgentData.mobile` false
- 1912px-wide desktop viewport on a 1080p monitor (mobile meta viewports are ignored)
- no `m.` / mobile redirects (YouTube, Google, Wikipedia, Reddit, X checked)

There's no tab cap. YouTube plays with sound, and a two-finger tap opens Chrome's
real right-click menu.

## How it works

- **Views on iOS.** A new `NativeWidgetIOS` hosts Views widgets in UIKit, with
  Chromium's compositor drawing into a CALayer tree. No Aura.
- **Single-process.** Browser, renderer and GPU share one process, the way iOS
  apps have to.
- **Jitless.** V8 runs without a JIT (DrumBrake handles Wasm), so it works under
  normal iOS code-signing rules.
- **iOS 27 external-display scene.** The browser window lives in the
  `UIWindowSceneSessionRoleExternalDisplayNonInteractive` scene, so the monitor
  gets its own full-screen window instead of mirroring the phone.
- **Trackpad.** The phone's scene is a trackpad: one finger moves the cursor,
  tap clicks, two fingers scroll, two-finger tap right-clicks.

Desktop-only features with no iOS equivalent (profile picker, default-browser
prompt, enterprise dialogs and so on) are stubbed out. Each one is listed in
[docs/desktop-chrome-ios-plan.md](docs/desktop-chrome-ios-plan.md).

## Status

Runs on an iPhone 16 Pro (iOS 27) with an external monitor. The checks above
were run in the iOS 27.2 Simulator with an external display; see
[docs/desktop-mode-verification.md](docs/desktop-mode-verification.md) and
[docs/views-ios-verification-2026-11-19.md](docs/views-ios-verification-2026-11-19.md).
It has only been tried on one phone so far.

It's **sideload only**: you build it and sign it with your own Apple developer
account. There is no IPA to download.

Limitations:

- No JIT by default, so heavy JavaScript is slower than desktop Chrome.
- Accessibility (VoiceOver) is not ported.
- Ctrl keyboard shortcuts are only partly wired up.
- One process, so a crashing page takes the whole browser with it.

## Build it yourself

You need a Mac with Xcode, [depot_tools](https://chromium.googlesource.com/chromium/tools/depot_tools.git),
100+ GB of free disk, an iPhone running iOS 27, and an Apple developer account.

1. Get a Chromium iOS checkout:
   ```sh
   mkdir chromium && cd chromium
   fetch --no-history ios
   cd src
   ```
   The patches were made against Chromium `main` in November 2026, so a newer
   checkout may need some rebasing.
2. Apply `patches/chromium-ios/` in numeric order. Most are git diffs
   (`git apply --3way NNNN-*.patch`). Some are file replacements: their
   `.patch` file is just a header saying so, and you copy `NNNN-files/` over
   `src/` (`NNNN-file-list.txt` lists the files and `NNNN-files/README.md`
   explains the step). Where two patches share a number, apply both.
3. Configure. Edit the bundle IDs in the args file to ones under your team:
   ```sh
   mkdir -p out/Release-iphoneos-views
   cp /path/to/chrome-desktop-ios/scripts/chromium-ios/args-views-device.gn \
      out/Release-iphoneos-views/args.gn
   gn gen out/Release-iphoneos-views
   ```
   Use `args-views-simulator.gn` for the Simulator.
4. Build:
   ```sh
   autoninja -C out/Release-iphoneos-views chrome/browser/ui/views/ios:chrome_views_ios
   ```
5. Sign with your own team. You need an explicit App ID profile with the
   increased-memory-limit and extended-virtual-addressing entitlements
   (`scripts/chromium-ios/chromeviews-appid-stub/` gets Xcode to make one). Then:
   ```sh
   export CHROMIUM_SRC=/path/to/chromium/src TEAM_ID=... SIGN_IDENTITY=... PHONE_UDID=...
   scripts/chromium-ios/sign-chrome-views-device.sh   # writes out/Release-iphoneos-views/ChromeDesktop-device.ipa
   xcrun devicectl device install app --device "$PHONE_UDID" \
     "$CHROMIUM_SRC/out/Release-iphoneos-views/ChromeDesktop-device.ipa"
   ```
6. Plug in a monitor (USB-C to DisplayPort/HDMI) and open the app.

More detail is in [scripts/chromium-ios/README.md](scripts/chromium-ios/README.md)
and [docs/](docs/).

## Not affiliated

This is an unofficial personal project. It is not affiliated with, endorsed
by, or supported by Google, the Chromium project, or Apple. Chrome and
Chromium are trademarks of Google LLC.

## License

BSD-3-Clause; see [LICENSE](LICENSE). Chromium code keeps Chromium's license
and copyright headers.
