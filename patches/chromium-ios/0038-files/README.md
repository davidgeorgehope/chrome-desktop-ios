Use desktop popular-sites behavior in the iOS Views build.

Apply after 0037. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
The desktop grit platform deliberately omits mobile baked-in popular-site JSON. Return the same empty fallback as desktop for ENABLE_IOS_DESKTOP_VIEWS instead of referencing missing mobile resources. Also restore the original ChromeOS-only ONC extension dependencies; the GN walker had incorrectly hoisted them out of that condition.

Status (18 Nov 2026, 11:41 PM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
