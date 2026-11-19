Views M2 compile: resolve chrome::DIR_EXTERNAL_EXTENSIONS on
iOS without using base::DIR_MODULE, which is not defined there.

Apply after 0035. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. Do not treat the 0026
look-alike shell as BrowserView, and do not build further on it.

What this patch does
--------------------
- For DIR_EXTERNAL_EXTENSIONS on iOS, use DIR_ASSETS (the app bundle)
  plus an "extensions" subdirectory instead of DIR_MODULE.

Status (18 Nov 2026, 11:24 PM ET)
--------------------------------
chrome_paths.o compiles. Full compile of browser_view_ios has been
restarted (4426 steps had already succeeded). This is not
BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
Device args.gn stays without enable_ios_desktop_views.
