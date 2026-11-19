iOS Views event monitor, policy path parser, download UI, relaunch banner

Apply after 0074. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Add views::EventMonitor for iOS (cursor location only for now) and a Foundation port of the Mac policy path parser. Link //chrome/browser/ui/download and the password manager relaunch banner as on Mac. Keep chrome://apps off on iOS; fix the memory_details_ios include.

Status (19 Nov 2026, 5:47 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
