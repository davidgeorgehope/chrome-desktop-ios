Install the native display Screen on iOS Views

Apply after 0097. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
ChromeBrowserMainExtraPartsViews owns a display::ScopedNativeScreen for ENABLE_IOS_DESKTOP_VIEWS, created in PreCreateThreads as ChromeBrowserMainExtraPartsMac does. Fixes the null Screen SEGV in RenderWidgetHostViewIOS; the first tab and BookmarkBarView are now built.

Status (19 Nov 2026, 8:19 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
