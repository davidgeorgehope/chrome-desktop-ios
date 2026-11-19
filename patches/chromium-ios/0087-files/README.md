chrome_views_ios links: last desktop cuts and ports on iOS Views

Apply after 0086. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Host link now succeeds with 0 undefined symbols. Ports/builds: enable_guest_contents for iOS Views, controlled_frame dep in chrome/common, chrome_web_contents_menu_helper, IWA key distribution installer policy, background_mode_manager_mac.cc reused, removable_storage_provider_ios.cc (empty list). Cuts: session restore infobar member, UpdateMetricsProvider (desktop session metrics kept), CBCM remote commands. components/resources: iOS Views drops components/management resources (duplicate kManagementResources with chrome's).

Status (19 Nov 2026, 7:08 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
