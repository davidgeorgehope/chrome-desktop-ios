Build SaaS usage and idle dialogs; cut desktop device signals on iOS Views

Apply after 0083. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
enterprise BUILD.gn: SaaS usage reporting sources (shared by Android and desktop) and idle/dialog_manager.cc built for iOS Views; chrome/browser deps on the Views enterprise startup and idle dialogs. Cuts: device signals collectors except profile signals, system signals host, browser signals decorator, managed-profile-required throttle hook, browser launch event controllers (nullptr like Android). Host link: 79 -> 61 undefined symbols.

Status (19 Nov 2026, 6:51 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
