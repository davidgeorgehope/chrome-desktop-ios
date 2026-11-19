# linux-ios-fast

Real desktop Chrome on an iPhone.

This repo holds patches and scripts that build Chromium's actual desktop
browser for iOS: the Blink engine plus the desktop Views UI (`BrowserView`,
tab strip, toolbar, omnibox, right-click menus). It draws on an external
monitor plugged into the phone, and the phone's own screen becomes a
trackpad and keyboard. It is not a remote desktop, a WKWebView wrapper, or a
mobile site. Pages load in desktop mode (macOS user agent, desktop viewport).

It also has:

- A jitless Blink build of the regular iOS Chromium app (`patches/chromium-ios/`,
  early numbers), with optional JIT experiments for iOS 27 / A18 Pro.
- Earlier experiments running Linux on iOS (Kernarium / UML, crate), with
  notes and benches in `NOTES.md`, `REPRODUCE.md` and `DESIGN.md`.

This is an unofficial personal project. It is not affiliated with, endorsed
by, or supported by Google, the Chromium project, or Apple.

## Status and limitations

- **Sideload only.** You build and sign it with your own Apple developer
  account. Apple only allows non-WebKit browser engines in the App Store in
  the EU, and this isn't there.
- **Single-process.** Browser, renderer and GPU run in one process.
- **No JIT by default.** V8 runs jitless (with DrumBrake for Wasm). The JIT
  builds are experiments and need specific iOS/hardware support.
- **Accessibility is not ported.** Several desktop-only features (profile
  picker, default-browser prompt, enterprise dialogs and so on) are stubbed;
  see `docs/desktop-chrome-ios-plan.md`.
- Tested on iOS 27 (Simulator and one iPhone). Expect rough edges.

## Building

You need a Mac with Xcode, depot_tools, a lot of disk (100+ GB), and an
Apple developer account.

1. Get a Chromium iOS checkout:
   ```sh
   mkdir chromium && cd chromium
   fetch --no-history ios
   cd src
   ```
   The patches were made against Chromium `main` in November 2026. On a newer
   checkout some will need rebasing.
2. Apply the patches in numeric order. Most are plain git diffs
   (`git apply --3way patches/chromium-ios/NNNN-*.patch`). Some later steps
   are file replacements instead: the `.patch` file is just a header saying
   so, and you copy the sources from `NNNN-files/` over the same paths in
   `src/` (`NNNN-file-list.txt` lists them, `NNNN-files/README.md` explains
   the step). Where two patches share a number, apply both.
3. Configure. For the desktop Views app on a device:
   ```sh
   mkdir -p out/Release-iphoneos-views
   cp /path/to/linux-ios-fast/scripts/chromium-ios/args-views-device.gn \
      out/Release-iphoneos-views/args.gn
   gn gen out/Release-iphoneos-views
   ```
   Use `args-views-simulator.gn` for the Simulator. Change the bundle IDs in
   the args file to ones under your own team.
4. Build:
   ```sh
   autoninja -C out/Release-iphoneos-views chrome/browser/ui/views/ios:chrome_views_ios
   ```
5. Sign with your own team. `scripts/chromium-ios/sign-chrome-views-device.sh`
   does it, using `TEAM_ID`, `SIGN_IDENTITY` and `PHONE_UDID` from the
   environment. It needs an explicit App ID provisioning profile with the
   increased-memory-limit and extended-virtual-addressing entitlements
   (`scripts/chromium-ios/chromeviews-appid-stub/` gets Xcode to make one).
   Install with `xcrun devicectl device install app`.

More detail is in `scripts/chromium-ios/README.md` and `docs/`.

## License

BSD-3-Clause for the original work here; see `LICENSE`. Chromium code and
patches keep Chromium's license and copyright headers, and patches to other
projects keep their upstream licenses.
