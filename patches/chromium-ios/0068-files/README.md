iOS Views platform_util, icon loader, accelerators, download bubble

Apply after 0067. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Add platform_util_ios.mm (UIKit window queries, no-op file reveal/open), reuse Android's portable icon loader and no-op global accelerator listener, build the Views accelerator table lookup, and link the download bubble, screen-capture notification and app shortcut dialog Views as on Win/Linux.

Status (19 Nov 2026, 4:38 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
