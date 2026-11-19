Create the geolocation permission manager on iOS Views

Apply after 0095. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
BrowserProcessPlatformPartBase::PreMainMessageLoopRun calls a new browser_process_platform_part_ios.mm helper that installs device::GeolocationSystemPermissionManager from SystemGeolocationSourceApple, as browser_process_platform_part_mac.mm does. Fixes the null-observe SEGV in LocationBarView during ToolbarView::Init; launch now reaches the first navigation.

Status (19 Nov 2026, 8:11 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
