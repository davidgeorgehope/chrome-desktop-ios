Add the iOS BrowserNativeWidget and frame view factories.

Apply after 0049. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
BrowserNativeWidgetIOS wraps views::NativeWidgetIOS, which prefers the external display (TVOut) scene. BrowserNativeWidgetFactory::Create returns it on iOS desktop Views. chrome::CreateBrowserFrameView returns OpaqueBrowserFrameView (or PictureInPictureBrowserFrameView for floating browsers). //chrome/browser depends on all three under is_ios && enable_ios_desktop_views.

Status (19 Nov 2026, 1:20 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
