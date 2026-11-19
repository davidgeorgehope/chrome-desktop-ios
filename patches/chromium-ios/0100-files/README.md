Let UIKit own the browser main loop on iOS Views

Apply after 0099. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
ChromeMainDelegate::RunProcess on iOS initializes a leaked content::BrowserMainRunner for the browser process and returns 0, as ShellMainDelegate does on iOS, instead of running BrowserMain's loop (MessagePumpUIApplication::DoRun is NOTREACHED). The app now stays up with BrowserView created; it ran ~3 minutes on the iOS 27 simulator.

Status (19 Nov 2026, 8:31 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
