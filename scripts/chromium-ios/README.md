# iOS Simulator content_shell

Bring up Blink `content_shell` in the iOS Simulator in desktop mode
(desktop user-agent, never the mobile site).

## Why the first launch was a gray page

Two separate problems stacked:

1. **BrowserEngineKit extensions do not start in this Simulator build.**
   iOS content_shell launches the renderer, GPU, and network processes
   through BrowserEngineKit (`BEWebContentProcess` /
   `BERenderingProcess` / `BENetworkingProcess`). Chromium's
   `codesign.py` only passes `--entitlements` for non-simulator
   platforms, so the app and its `.appex` bundles are adhoc-signed with
   an empty entitlement set. The system then fails to install/launch
   the extensions (`Install Failed: Authorization is required to
   install the packages.`). Re-signing adhoc *with* the generated
   `.xcent` (including `com.apple.developer.web-browser-engine.*`)
   makes SpringBoard deny the launch entirely (`NSPOSIXErrorDomain`
   163, "Launchd job spawn failed") because those are restricted
   entitlements and are not valid on an adhoc signature.

2. **`--single-process --in-process-gpu` paints, but did not host the
   layer.** Avoiding the extensions works for loading and raster, but
   `InProcessGpuThread::ForwardBELayerHierarchyToBrowser` is a no-op,
   so the `BELayerHierarchy` produced by the GPU path was never
   attached to the `BELayerHierarchyHostingView`. The UIKit toolbar
   drew and the URL updated; the content view stayed gray.

The fix for (2) is
`patches/chromium-ios/0001-in-process-belayer-host.patch`. Apply it
from `chromium/src` and rebuild `content_shell`. It attaches the
handle (or, if `BELayerHierarchy` itself fails, falls back to a
direct `CALayer` sublayer).

## Run

On the Mac mini, after the patch is built into
`out/Release-iphonesimulator/content_shell.app`:

```
scripts/chromium-ios/resign-and-run-content-shell-sim.sh boot
scripts/chromium-ios/resign-and-run-content-shell-sim.sh run https://example.com/ example
scripts/chromium-ios/resign-and-run-content-shell-sim.sh shutdown
```

`run` always passes `--single-process --in-process-gpu` and a desktop
Chrome user-agent. iOS `ContentMain` still appends
`--use-mobile-user-agent` and `--enable-viewport`, but a custom
`--user-agent` wins for the HTTP User-Agent header (Google then
serves the desktop homepage).

The `resign` subcommand is kept for experiments with a real
development identity. Adhoc + BrowserEngineKit entitlements is *not*
a working Simulator path.

# iOS Simulator Chrome (Chrome UI on Blink)

Goal was Chrome's *desktop* Views UI (tab strip, omnibox, toolbar) in the
Simulator. That UI cannot be built for iOS from upstream:

- `chrome/BUILD.gn` (and ~18 other //chrome BUILD files) hard-assert
  `assert(!is_ios, "Chromium/iOS shouldn't use anything in //chrome")`.
- `build/config/ui.gni`: `toolkit_views = is_mac || is_win || is_linux ||
  is_chromeos || is_fuchsia` and `use_aura` excludes iOS. There is no
  UIKit `NativeWidget` in `ui/views/widget/` (only Aura and Mac/AppKit).
- Upstream's Blink-on-iOS work (docs/ios/build_instructions.md,
  "Building Blink for iOS") reuses the *iOS Chrome* UI (`//ios/chrome`) and
  swaps the web layer for Blink via `//ios/web/content` (ContentWebState).

So the closest real Chrome UI that builds is the upstream `chrome` target
with `use_blink = true`: Chrome's own UIKit browser UI driving real
Blink/V8 content (no WKWebView). On an **iPad** Simulator the regular-width
layout gives a desktop-style tab strip + omnibox + toolbar.

Build (same out dir/args as content_shell; siso state does not survive
cloning an out dir, so a separate dir means a full ~2h rebuild):

```
~/chromium-build/run-chrome-ios-build.sh      # autoninja -j8 chrome, pokes webhook on finish
```

Run:

```
scripts/chromium-ios/run-chrome-ios-blink-sim.sh run https://www.whatismybrowser.com/ tag
```

Notes:
- `--single-process --in-process-gpu` (same BrowserEngineKit/adhoc
  limitation as content_shell, needs patch 0001).
- `--disable-features=NetTaskScheduler,NetworkServiceTaskScheduler`: in
  single-process the iOS in-process NetworkService on the IO thread picks
  up the content network thread's `net::TaskRunnerGlobals` and fails
  `SimpleWatcher`'s `RunsTasksInCurrentSequence` DCHECK.
- URLs are opened via `chromiums://` (Safari is the sim's default browser);
  SpringBoard's "Open in Chromium?" alert is confirmed with AXe
  (`brew install cameroncooke/axe/axe`). The sim is freshly booted per run
  because queued URL contexts trip `DCHECK(!_sceneState.URLContextsToOpen)`.

Desktop mode is always on via
`patches/chromium-ios/0002-ios-blink-always-desktop-mode.patch`:
no `--use-mobile-user-agent`/`--enable-viewport` from iOS ContentMain,
macOS UA (`Macintosh; Intel Mac OS X 10_15_7`), UA-CH `mobile=?0`,
`platform="macOS"`, `navigator.platform = "MacIntel"`, fine pointer +
hover, `maxTouchPoints = 0`, no touch-event feature detection.
