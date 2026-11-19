Cut first run and desktop signin/profile services on iOS Views

Apply after 0080. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
chrome_browser_main_extra_parts_profiles.cc: narrowed browser switcher, enterprise signin, Gapis, profile token / OIDC policy and interceptor factories back to their desktop platforms; accounts policy manager, FirstRunService and profile management disclaimer factories !IS_IOS. startup_browser_creator.cc: no FRE on iOS, --list-apps narrowed. web_app_startup_utils.cc built for iOS Views (Mac parity). Host link: 146 -> 130 undefined symbols.

Status (19 Nov 2026, 6:38 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
