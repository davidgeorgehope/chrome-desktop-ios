Use Mac relaunch banner strings for iOS desktop Views

Apply after 0075. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
The iOS desktop Views grit pass is darwin, so use Mac's relaunch banner title/description string IDs.

Status (19 Nov 2026, 5:50 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
