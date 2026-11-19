Treat desktop-platform #if gates as on for iOS Views.

Apply after 0041. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
tools/ios-desktop-views/widen-desktop-gates.py appends || BUILDFLAG(ENABLE_IOS_DESKTOP_VIEWS) to #if/#elif conditions that are only an OR of desktop platforms including IS_MAC and IS_WIN or IS_LINUX. Applied to chrome/browser, chrome/common, chrome/renderer and components (1101 gates in 424 files; tests and android/ash/chromeos/win/linux dirs skipped). Mac-only and negated gates are unchanged. The device build is unaffected because the flag is off there.

Status (19 Nov 2026, 12:00 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
