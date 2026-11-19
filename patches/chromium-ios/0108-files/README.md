iOS Views: real owned/child widget enumeration in NativeWidgetIOS

Apply after 0107. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
NativeWidgetIOS records its owning widget from InitParams::parent and ReparentNativeViewImpl (refusing cycles; cleared when the parent is destroyed). NativeWidgetPrivate::GetAllOwnedWidgets now returns widgets transitively owned by the given view's widget, excluding itself, as widget.h requires; GetAllChildWidgets includes itself. Previously GetAllOwnedWidgets returned the widget itself, so BrowserView::GetAccessibleWindowTitle treated the browser window as a focused tab-modal and recursed forever on every navigation state change.

Status (19 Nov 2026, 10:01 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
