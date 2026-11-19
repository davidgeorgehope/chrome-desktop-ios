Views M2 GN walk (in progress): start loading the real
//chrome/browser/ui/views/frame:browser_view graph on iOS behind
enable_ios_desktop_views.

Apply after 0026. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. Do not treat the 0026
look-alike shell as BrowserView. This patch only walks and opens the
real //chrome Views targets.

What this patch does
--------------------
- Adds //chrome/browser/ui/views/ios:browser_view_ios, a group that
  depends on the real :browser_view, hooked from
  //ui/views:chrome_browser_view_ios so an iOS gn gen loads the
  graph.
- Widens per-target platform asserts (assert(!is_ios),
  assert(is_win || is_mac || ...)) to also allow
  (is_ios && enable_ios_desktop_views). The root //chrome:chrome
  assert in chrome/BUILD.gn is intentionally not lifted.
- Gates extensions deps on enable_extensions_core (which stays off
  on iOS). Desktop extensions remain stubbed, per the plan.
- Moves chrome/browser/devtools/BUILD.gn's
  import("//chrome/common/features.gni") out of a conditional so
  enable_service_discovery is defined when the file is parsed.
- Ports ui/native_window_tracker to iOS (WeakUIWindow). This is a
  real implementation, not a fake chrome shell.

Status (18 Nov 2026, 8:29 PM ET)
--------------------------------
gn gen of out/Release-iphonesimulator-views with the probe hooked
is not yet green. The next failure after this snapshot is:

  ERROR at //chrome/browser/ui/extensions/BUILD.gn:8
  assert(enable_extensions_core)
  included from //chrome/browser/ui/BUILD.gn (~1985)
    "//chrome/browser/ui/extensions",

The walker in tools/ios-desktop-views/walk-gn-asserts.py can
continue widening platform asserts and moving enable_* deps under
feature-flag conditions. After gn gen succeeds, the C++ compile
wall remains: unguarded includes, Mac/Aura-only APIs, then a real
Browser + Profile + BrowserView host on the M1 TVOut path, then a
Blink WebContents.

chrome/test/BUILD.gn's !is_ios assert is widened in this snapshot
because a dep in the graph reached that file; the flag-off device
build is unchanged.

Replace the listed files with the copies in this directory (they
are complete current sources). New files:
  chrome/browser/ui/views/ios/BUILD.gn
  ui/native_window_tracker/native_window_tracker_ios.cc
  ui/native_window_tracker/native_window_tracker_ios.h
