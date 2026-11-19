Narrow desktop-only throttles/binders; iOS view delegate, color listener, AI overlay

Apply after 0072. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Bulk widening had enabled Win/Mac/Linux-only navigation throttles, the browser switcher, the first-run field trial, Web Share and ProfilePickerUI binders, and scheduled restart on iOS Views; narrow those back. Add a null WebContentsViewDelegate for iOS (Aura/Cocoa delegates do not apply), build the color change listener handler and the AI overlay dialog WebUI, and link headless metrics.

Status (19 Nov 2026, 5:30 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
