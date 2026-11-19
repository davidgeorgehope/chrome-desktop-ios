Enable the Instant extended API on iOS Views

Apply after 0096. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
search::IsInstantExtendedAPIEnabled returns true for ENABLE_IOS_DESKTOP_VIEWS, matching desktop, so InstantServiceFactory works with the desktop WebUI NTP. Fixes the CHECK in ChromeContentBrowserClient::AppendExtraCommandLineSwitches at the first renderer launch.

Status (19 Nov 2026, 8:18 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
