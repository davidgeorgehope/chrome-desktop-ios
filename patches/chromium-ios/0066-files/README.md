Fix web app OS-integration stubs for iOS Views

Apply after 0065. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
web_app_stubs.cc had drifted from the headers: run-on-login now uses ResultCallback / Result, and the shortcut create/update stubs run their callbacks instead of dropping them.

Status (19 Nov 2026, 4:31 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
