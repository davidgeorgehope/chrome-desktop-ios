Use desktop home-modules registry behavior on iOS Views

Apply after 0092. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
HomeModulesCardRegistry::Create returns nullptr for ENABLE_IOS_DESKTOP_VIEWS, as on desktop, instead of building the iOS magic-stack registry whose prefs desktop Chrome never registers. Fixes the unregistered ephemeral_pref_counter FATAL.

Status (19 Nov 2026, 7:54 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
