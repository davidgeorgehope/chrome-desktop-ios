iOS Views: don't stretch native subview layers in the widget content view

Apply after 0113. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
DeskBrowserViewsContentView -layoutSubviews resized every sublayer to the content bounds, including the backing layer of the WebContents UIScrollView that NativeViewHostIOS positions, so the page covered the tab strip and toolbar. Skip layers whose delegate is a UIView; only compositor layers are stretched. example.com now renders in the 1912x928 contents area at (4,148) on TVOut.

Status (19 Nov 2026, 10:48 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
