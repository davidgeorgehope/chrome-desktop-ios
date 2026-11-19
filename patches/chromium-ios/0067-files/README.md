Enable the DevTools frontend for iOS desktop Views

Apply after 0066. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Mac parity: DevToolsWindow, DevToolsUI and the availability checker are referenced by extensions and tabs code. Flip enable_devtools_frontend on when enable_ios_desktop_views is set; mobile iOS is unchanged.

Status (19 Nov 2026, 4:38 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
