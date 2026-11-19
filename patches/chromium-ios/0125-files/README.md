NativeWidgetIOS: make Views menus work (app menu)

Apply after 0124. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Opening the app menu crashed in MenuHost::ShowMenuHost: NativeWidgetIOS::GetGestureRecognizer returned null. It now returns a static ui::GestureRecognizerImplMac (the platform-neutral Mac no-op stub, which ui/events now also builds for iOS). After that the menu covered the whole TVOut screen in white: InitNativeWidget maximized every widget on a desktop-sized scene; now only parentless TYPE_WINDOW widgets are maximized there (Init and MoveToPreferredScene). Menu contents were then blank because RootView stayed 0x0 (menus keep Init bounds and never SetBounds); OnWidgetInitDone sends OnNativeWidgetSizeChanged. GetNativeWidgetForNativeView now walks superviews so hosted views (WebContents UIScrollView) resolve to their widget, as on Mac/Aura. Verified: trackpad click on the app menu button shows the full Chrome app menu at 1492,85 418x716 on TVOut.

Status (19 Nov 2026, 12:35 PM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
