iOS Views ports: NativeViewHost, keyboard, window sizer, tab drag input

Apply after 0076. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Real iOS pieces for the window and tab UI: NativeViewHostIOS hosts the WebContents UIView in the NativeWidgetIOS content view; UnhandledKeyboardEventHandler rebuilds a ui::KeyEvent from the Blink event for Views accelerators; WindowSizer popup origin from display::Screen; tabs_api drag input adapter over views::EventMonitor; ChromeViewsDelegate uses content's context factory (Mac file, IS_APPLE); RunDragDropLoop (Mac no-op file); GetMenuSourceTypeForEvent built; UIKit ResizedImageForMaxDimensions. Cuts (listed in docs/desktop-chrome-ios-plan.md): Chrome Apps windows, desktop capture window icons, storage monitor dummy, generic quarantine no-op. Inactive window mouse controller built. Host link: 253 -> 233 undefined symbols.

Status (19 Nov 2026, 6:20 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
