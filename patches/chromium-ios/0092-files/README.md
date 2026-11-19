Register supervised-user extension migration pref on iOS Views

Apply after 0091. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
supervised_user_preferences.cc registers profile.managed.locally_parent_approved_extensions_migration_state for ENABLE_IOS_DESKTOP_VIEWS, matching pref_names.h and SupervisedUserExtensionsManager. Fixes the unregistered-pref FATAL at launch.

Status (19 Nov 2026, 7:51 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
