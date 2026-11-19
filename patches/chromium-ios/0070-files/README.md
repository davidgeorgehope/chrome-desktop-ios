No-op app shortcut dialog for iOS Views

Apply after 0069. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
The Win/Linux CreateApplicationShortcutView uses strings grit only emits for non-Apple targets, and iOS has no home screen shortcut to make. Add create_application_shortcut_ios.cc that reports nothing was created.

Status (19 Nov 2026, 5:08 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
