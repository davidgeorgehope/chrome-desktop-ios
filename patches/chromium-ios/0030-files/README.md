Views M2 GN walk: gn gen of //chrome/browser/ui/views/frame:browser_view
is green on iOS behind enable_ios_desktop_views.

Apply after 0029. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. Do not treat the 0026
look-alike shell as BrowserView, and do not build further on it.

What this patch does
--------------------
- Fixes the walker's same-file ":name" dep matching and enclosing-if
  attribution (sibling ifs are no longer treated as the enclosing
  condition). Wraps are scoped to the from-target, already-gated
  mentions use brace-accurate enclosure, and grit("foo") is found
  when the missing label is foo_grit.
- Wraps the remaining unresolved deps under their feature flags
  rather than widening lone is_mac / is_linux edges:
  enable_dice_support (profile picker controllers), enable_printing,
  enable_captive_portal_detection, enable_extensions_core
  (component_extension_resources_grit, managed_ui_handler).
- Updates tools/ios-desktop-views/walk-gn-asserts.py accordingly.

Status (18 Nov 2026, 9:59 PM ET)
--------------------------------
gn gen out/Release-iphonesimulator-views succeeded (44915 targets
from 5986 files). Next is the C++ compile wall, then a real
Browser + Profile + BrowserView host on the M1 TVOut path.

Replace the listed files with the copies in this directory (they
are complete current sources). Device args.gn stays without
enable_ios_desktop_views.
