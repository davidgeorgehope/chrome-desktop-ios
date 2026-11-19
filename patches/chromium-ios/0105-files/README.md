Report one display per UIScreen on iOS Views

Apply after 0104. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
ScreenIos (ENABLE_IOS_DESKTOP_VIEWS) builds a display::Display per UIScreen, makes the external screen the primary display at the origin with the phone panel to its right, answers GetDisplayNearestWindow/View from the window's UIScreen, and refreshes on scene connect/disconnect. GetCursorScreenPoint returns the primary display center and ui::CalculateIdleTime returns 0 instead of NOTIMPLEMENTED spam.

Status (19 Nov 2026, 9:21 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
