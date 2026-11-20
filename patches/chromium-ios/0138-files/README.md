iOS Views: close client-owned widgets and lay out on frames

Apply after 0137. Used by the desktop Views app (chrome_views_ios,
out/Release-iphoneos-views and the simulator). The ios/chrome Chromium.app
device build keeps enable_ios_desktop_views off.

What this patch does
--------------------
New-tab crash. Opening a tab runs BrowserView::UpdateTitleBar, which asks for the accessible window title, which walks NativeWidgetPrivate::GetAllOwnedWidgets over every NativeWidgetIOS. Widgets with CLIENT_OWNS_WIDGET ownership (bubbles, the omnibox popup, hover cards) were never deleted after closing: NativeWidgetIOS::CloseNow only deleted itself for NATIVE_WIDGET_OWNS_WIDGET, and ClientDestroyedWidget was not implemented, so the closed native widget stayed in the view map with delegate_ pointing at the freed Widget. The next walk built a raw_ptr<Widget> from freed memory and PartitionAlloc's BackupRefPtr check trapped (CHECK in GetAllOwnedWidgets, seen on device).

- ClientDestroyedWidget() drops delegate_, focus observation and capture as soon as the client destroys its Widget.
- CloseNow() deletes the native widget for CLIENT_OWNS_WIDGET as well as NATIVE_WIDGET_OWNS_WIDGET (as NativeWidgetMac::WindowDestroyed does) and only sends OnNativeWidgetDestroyed once.
- GetAllOwnedWidgets() skips closing widgets and widgets without a Widget.

Deferred layout. ScheduleLayout() only re-invalidated the RootView, and NativeWidgetIOS did not implement LayerDelegate::UpdateVisualState(), so a deferred Views layout ran only when something else forced one. A new tab stayed at its zero-width insertion size until the user switched tabs. ScheduleLayout() now schedules a compositor frame and UpdateVisualState() runs Widget::LayoutRootViewIfNecessary(), as NativeWidgetMac and NativeWidgetAura do.

Simulator check: omnibox popup opened and closed, then Cmd+T, the tab strip + button and a target=_blank link each open a tab; the app stays alive and the new tab is drawn at full width without switching tabs.

Replace the listed files with the copies in this directory.
