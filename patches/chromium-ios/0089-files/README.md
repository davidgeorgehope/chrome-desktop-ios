Bundle Apple-named locales and register Mac content settings on iOS Views

Apply after 0088. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Launch progress on the iOS 27 simulator: locale.pak lookup failed (bundle had en-US.lproj; iOS ResourceBundle asks NSBundle for en / en_GB), and DefaultProvider hit NOTREACHED for FileSystemAccess settings that are registered only for desktop. chrome_paks.gni: is_apple uses locales_as_apple_outputs. website_settings_registry.cc: with ENABLE_IOS_DESKTOP_VIEWS, register entries marked for Mac or iOS.

Status (19 Nov 2026, 7:17 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
