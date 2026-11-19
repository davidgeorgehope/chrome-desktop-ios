Chrome main delegate and host entry compile fixes for iOS Views

Apply after 0063. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
- chrome_main_delegate.cc: the Linux/Android crashpad start-up and the SIGTERM profiling handler are not used on iOS (IS_APPLE excluded, as Mac).
- chrome_views_ios_main.mm: the ContentMainRunner and ChromeMainDelegate are leaked raw pointers instead of global unique_ptrs (no exit-time destructors).

Status (19 Nov 2026, 4:01 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
