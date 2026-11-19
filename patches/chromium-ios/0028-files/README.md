Views M2 GN walk (in progress): continue loading the real
//chrome/browser/ui/views/frame:browser_view graph on iOS behind
enable_ios_desktop_views.

Apply after 0027. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. Do not treat the 0026
look-alike shell as BrowserView, and do not build further on it.

What this patch does
--------------------
- Continues the GN walk started in 0027: widen per-target platform
  asserts with (is_ios && enable_ios_desktop_views), and gate
  feature-flag deps (enable_extensions_core, enable_webui_ntp,
  enable_pdf, enable_guest_view, enable_dice_support,
  enable_platform_apps, enable_printing, enable_screen_ai_service,
  and others) so those features stay off on iOS unless already on.
- Does not lift the root assert(!is_ios) in chrome/BUILD.gn or
  chrome/test/BUILD.gn (0027 had widened chrome/test; this snapshot
  puts both back). Incoming deps on //chrome/test:test_support are
  wrapped in if (!is_ios) instead, so the desktop test graph is not
  pulled into the iOS views out dir.
- Restores //extensions/buildflags deps as unconditional (they
  provide BUILDFLAG headers even when extensions are off), with
  if (!defined(deps)) guards when the assignment would otherwise
  run after a false feature/platform if.
- Ports and updates tools/ios-desktop-views/walk-gn-asserts.py:
  auto-import the .gni that defines a flag, wrap compound asserts,
  handle build_webui / .gni list deps, refuse to widen the chrome
  root asserts, and start repairing "Unresolved dependencies" by
  widening platform ifs or wrapping feature-gated deps.
- Adds missing import("//extensions/buildflags/buildflags.gni")
  (and other feature .gni files) at file scope when a BUILD.gn
  references the flag.

Status (18 Nov 2026, 9:24 PM ET)
--------------------------------
gn gen of out/Release-iphonesimulator-views with the probe hooked
is not yet green. After this snapshot the walker is wrapping
remaining //chrome/test:test_support deps under if (!is_ios) and
then will resume other feature/platform failures.

After gn gen succeeds, the C++ compile wall remains: unguarded
includes, Mac/Aura-only APIs, then a real Browser + Profile +
BrowserView host on the M1 TVOut path, then a Blink WebContents.

Replace the listed files with the copies in this directory (they
are complete current sources). New or updated relative to 0027
include tools/ios-desktop-views/walk-gn-asserts.py and a large
set of chrome/, components/, and ui/ BUILD.gn files. Device
args.gn stays without enable_ios_desktop_views.
