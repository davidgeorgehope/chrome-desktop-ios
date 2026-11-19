Resolve first host link errors for iOS Views

Apply after 0064. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Host link of chrome_views_ios (04:02 AM ET) was missing 19 symbols:
- ui/gfx: new native_ui_util_ios.mm GetViewForWindow (root view controller view, else the window).
- web apps: os_integration/web_app_stubs.cc provides no-op shortcut, file-handler and run-on-login integration; icon masking is the identity, as on Linux/Windows.
- sessions: the content-based components/sessions (SessionTabHelper, live tabs) is used for iOS Views instead of the ios/web one.
- system.cpu uses the Mach-based Mac provider; LoginDatabase uses the Mac os_crypt encryptor; Firefox profile lookup uses the Mac base-path implementation (no Safari importer).
- the host depends on devtools_pipe; chrome/browser depends on security_events (Mac gets it through Safe Browsing).

Status (19 Nov 2026, 4:12 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
