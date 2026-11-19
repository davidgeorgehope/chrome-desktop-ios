iOS Views first run, notifications, status tray, shell integration

Apply after 0071. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
No installer/relaunch on iOS: first_run_internal_ios.cc stubs. Skip the system notification bridge (message center fallback) and the profile picker hide; reuse Android's portable status tray and shell integration stubs; build the web store navigation throttle.

Status (19 Nov 2026, 5:20 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
