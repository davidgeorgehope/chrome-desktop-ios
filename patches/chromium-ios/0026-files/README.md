Views Milestone 2 (first visible chrome): a desktop-style tab strip,
toolbar/omnibox, and contents pane paints on the iOS 27 Simulator
TVOut as a Views widget, behind enable_ios_desktop_views.

Apply after 0025 (Views M1 TVOut paint). This does not go into the
device IPA; keep enable_ios_desktop_views off for device builds.

This is a Chrome-accurate Views shell in the existing
views_examples_ios TVOut host, not yet the real
chrome/browser/ui/views BrowserView. The real TabStrip / Toolbar /
Browser targets still assert off on iOS and pull a large desktop-only
GN graph (glic, Profile, themes, generated_resources). That walk is
the next step; do not treat this shell as BrowserView done.

What this patch does
--------------------
- Adds DesktopBrowserChromeView: a tab strip (Chrome Refresh tab
  shapes, New Tab / Welcome, + button), a toolbar with back / forward
  / reload, a rounded omnibox, and an app-menu glyph, laid out with
  Chromium non-touch layout_constants (tab strip 41, toolbar 52,
  location bar 34). Colors come from the already-registered ui::
  ColorProvider mixers (kColorSysHeader / kColorSysBase / surface).
- Replaces the M1 red MilestoneView as the widget contents and places
  the widget fullscreen on the official
  UIWindowSceneSessionRoleExternalDisplayNonInteractive scene.
- Leaves a phone-side trackpad on the application scene (the official
  external role is non-interactive). Touches map absolutely onto the
  1920x1080 widget, move a software cursor, and synthesize
  ui::MouseEvent press/release into the Views root.

Verified 8:03 PM ET on the iOS 27.2 iPhone Duo simulator
(UDID SIM-UDID), hinge 180, TVOut
1920x1080: 02-tvout.png shows the tab strip and toolbar; a later
axe tap on the inner LCD placed the software cursor in the contents
area (04-tvout-after-tap.png). The inner LCD shows the "Trackpad"
surface.

Replace the listed files with the copies under ui/ in this directory
(they are complete current sources). New files:
  ui/views/examples/ios/desktop_browser_chrome_view.h
  ui/views/examples/ios/desktop_browser_chrome_view.mm
Updated:
  ui/views/examples/ios/BUILD.gn
  ui/views/examples/ios/views_examples_ios_main.mm
