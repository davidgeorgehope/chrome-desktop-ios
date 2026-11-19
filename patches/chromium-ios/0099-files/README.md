Use desktop resource scale factors on iOS Views

Apply after 0098. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
ResourceBundle::InitSharedInstance registers 100P and 200P for ENABLE_IOS_DESKTOP_VIEWS, so the bundled chrome_100/200_percent paks load (iOS Chrome only enabled the panel scale, 300P, which we do not ship). Fixes the missing IDR_BOOKMARK_BAR_APPS_SHORTCUT bitmap; startup now completes PreMainMessageLoopRun.

Status (19 Nov 2026, 8:24 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
