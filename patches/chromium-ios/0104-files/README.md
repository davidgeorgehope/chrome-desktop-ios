Resize the Views root when a widget moves to TVOut

Apply after 0103. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
NativeWidgetIOS::MoveToPreferredScene now resizes through SetBounds (which calls Widget::OnNativeWidgetSizeChanged) instead of only syncing the UIWindow frame, and resyncs the compositor scale when bounds are unchanged. On the iOS 27 simulator the Chrome window fills the 1920x1080 TVOut scene and child dialogs re-center.

Status (19 Nov 2026, 8:57 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
