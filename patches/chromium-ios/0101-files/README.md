Keep feature engagement profile storage on iOS Views

Apply after 0100. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
IsOnDeviceStorageEnabled returns false on ENABLE_IOS_DESKTOP_VIEWS like desktop. Desktop Chrome uses the profile pref service for its Tracker; the iOS mobile device-storage migration instead needs local-state prefs and caused an unregistered-pref FATAL after ~3 minutes. App now runs past that point.

Status (19 Nov 2026, 8:40 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
