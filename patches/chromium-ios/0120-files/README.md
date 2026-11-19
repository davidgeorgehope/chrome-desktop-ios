NativeWidgetIOS: send OnNativeWidgetDestroying from CloseNow

Apply after 0119. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Widget::CloseNow() (used by StatusBubbleViews::DestroyPopup after a link-hover status bubble) calls NativeWidgetIOS::CloseNow directly, which notified OnNativeWidgetDestroyed without OnNativeWidgetDestroying and tripped CHECK(widget_destroying_handled_) in Widget::HandleWidgetDestroyed. CloseNow now sends the destroying notification once (guarded by destroying_notified_) before destroyed; Close() just forwards to CloseNow. Found while hovering Wikipedia links with the phone trackpad cursor.

Status (19 Nov 2026, 11:38 AM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
