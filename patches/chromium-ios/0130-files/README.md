iOS Views: menu keyboard, capture and close

Apply after 0129. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Context/app menus could open but not close or take keys. MenuPreTargetHandlerIOS was an empty stub; it now registers a NativeWidgetIOS::KeyEventMonitor (new static Add/Remove/HasKeyEventMonitor; DispatchTrackpadKeyEvent runs monitors newest first) and forwards to MenuController::OnWillDispatchKeyEvent unless a menu textfield has focus, like MenuPreTargetHandlerMac. NativeWidgetIOS::GetCaptureWindow exposes the capture widget; the phone trackpad routes pointer events there while it is set (so clicks outside a menu cancel it) and sends keys and Return to Views while a menu monitor exists. Closing a menu exposed three lifecycle bugs, all fixed: DestroyCompositor called SetAcceleratedWidget(null) (CHECK !widget_valid_) and now uses ReleaseAcceleratedWidget as Mac does; Close() destroyed the Widget synchronously inside Widget::CloseWithReason (CHECK !on_call_stack_) and now hides and posts CloseNow; ~NativeWidgetIOS freed the owned Widget while delegate_ still pointed at it (DanglingPtr) and now clears delegate_ first. The handler file is renamed to menu_pre_target_handler_ios.mm (ui/views/BUILD.gn updated); delete the old menu_pre_target_handler_ios.cc from 0017 when applying. Verified on example.com: two-finger tap opens the menu, Escape closes it, an outside click closes it, Down highlights Reload and Return reloads the page; a click on disabled Forward leaves the menu open; the app stays alive throughout.

Status (19 Nov 2026, 1:10 PM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
