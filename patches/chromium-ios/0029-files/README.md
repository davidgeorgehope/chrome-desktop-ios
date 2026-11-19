Views M2 GN walk (in progress): post-0028 walk edits toward a green
gn gen of //chrome/browser/ui/views/frame:browser_view on iOS
behind enable_ios_desktop_views.

Apply after 0028. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. Do not treat the 0026
look-alike shell as BrowserView, and do not build further on it.

What this patch does
--------------------
- Continues gating //chrome/test:test_support (and other
  //chrome/test targets that would parse chrome/test/BUILD.gn)
  under if (!is_ios), without lifting the root assert(!is_ios) in
  chrome/BUILD.gn or chrome/test/BUILD.gn.
- Retargets //chrome:strings and //chrome:resources to their leaf
  targets so those group labels do not parse chrome/BUILD.gn.
- Wraps remaining feature-flag deps (enable_printing,
  enable_captive_portal_detection, enable_dice_support, and others)
  and starts repairing "Unresolved dependencies" by widening
  multi-platform ifs or wrapping feature-gated deps.
- Does not widen lone if (is_mac) or if (is_linux) onto iOS; those
  incoming deps are wrapped instead (Mac app-shim / Linux shell
  integration stay platform-specific).
- Updates tools/ios-desktop-views/walk-gn-asserts.py to retarget
  string/resource groups, allow indented asserts, refuse
  single-OS if widens, and begin unresolved-dep repairs.

Status (18 Nov 2026, 9:49 PM ET)
--------------------------------
gn gen of out/Release-iphonesimulator-views is not yet green. The
walk is in the unresolved-deps phase. Two walker bugs remain and
are the next work: same-file deps written as ":name" are missed,
and enclosing_if_condition can pick the wrong if when walking
backward (e.g. first_run_flow_controller attributed to
safe_browsing_mode != 0; it is under if (enable_dice_support)).

After gn gen succeeds, the C++ compile wall remains, then a real
Browser + Profile + BrowserView host on the M1 TVOut path.

Replace the listed files with the copies in this directory (they
are complete current sources). Device args.gn stays without
enable_ios_desktop_views.
