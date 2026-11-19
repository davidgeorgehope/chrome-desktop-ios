Compile the real BrowserView graph on the iOS Simulator.

Apply after 0047. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Desktopizes components/webdata_services and components/browser_sync, so the desktop sync feature set is used consistently. The full chrome/browser/ui/views/ios:browser_view_ios compile is GREEN: Exit 0 on 19 Nov 2026 at 12:57 AM ET in out/Release-iphonesimulator-views. This target compiles the real BrowserView graph but does not yet link or host a BrowserView app. Next: link a real BrowserView host, add narrow platform stubs as needed, and run on simulated TVOut.

Status (19 Nov 2026, 1:04 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
