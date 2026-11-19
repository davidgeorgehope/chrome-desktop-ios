Add chrome_paths for desktop Views on iOS.

Apply after 0051. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
chrome/common/chrome_paths_ios.mm implements chrome_paths_internal inside the app sandbox. The profile goes in Library/Application Support/Chromium, and downloads, music, pictures and videos go in Documents subdirectories. It is built only for is_ios && enable_ios_desktop_views.

Status (19 Nov 2026, 1:33 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
