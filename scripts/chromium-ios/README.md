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
