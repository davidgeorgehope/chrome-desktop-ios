NativeWidgetIOS: trackpad input entry points and focus listener

Apply after 0116. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Adds static NativeWidgetIOS::DispatchTrackpadMouseEvent (routes ui::MouseEvent to the widget delegate) and DispatchTrackpadKeyEvent (InputMethod::DispatchKeyEvent, falling back to DispatchKeyEventPostIME) for the phone trackpad host. NativeWidgetIOS now listens to its FocusManager and calls [window endEditing:YES] when Views focus lands on a view with no NativeViewHost, so the WebContents' RenderWidget UIView stops being first responder when the omnibox is focused (mirrors NativeWidgetMacNSWindowHost::OnDidChangeFocus). Listener removed in CloseNow and the destructor.

Status (19 Nov 2026, 11:27 AM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
