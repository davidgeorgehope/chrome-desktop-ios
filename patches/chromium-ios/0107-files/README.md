iOS Views: NativeWidgetIOS layer/view dump and widget Show logging

Apply after 0106. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Diagnostics in ui/views/widget/native_widget_ios.mm: a delayed CALayer/UIView tree dump (up to 3) after MoveToPreferredScene for TYPE_WINDOW, and an NSLog of widget name/type/contents on Show. Temporary; used to identify the stray bubble widgets.

Status (19 Nov 2026, 9:48 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
