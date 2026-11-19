Create AtExitManager before UIApplicationMain in Chrome Views iOS

Apply after 0087. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
First iOS 27 simulator launch linked and installed successfully, then hit base/at_exit.cc:59 (about_flags FlagsStateSingleton) because ContentMainRunnerImpl deliberately does not create AtExitManager on iOS. Add it in main, matching content_shell ContentAppMain. Host rebuild/link succeeds.

Status (19 Nov 2026, 7:11 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
