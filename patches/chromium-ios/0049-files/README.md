Add the chrome_views_ios host app for the real BrowserView.

Apply after 0048. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
New //chrome/browser/ui/views/ios:chrome_views_ios ios_app_bundle runs Chrome's own ChromeMainDelegate in-process through content::RunContentProcess (the content_shell iOS pattern). chrome_dependencies_ios mirrors //chrome:dependencies without loading //chrome/BUILD.gn, and chrome_main_ios builds chrome_main_delegate.cc as Mac's chrome_dll does. gn gen is green with this root target. Full //chrome/browser, renderer, utility, gpu and common compile is running (about 24k steps, including Blink for this out dir).

Status (19 Nov 2026, 1:10 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
