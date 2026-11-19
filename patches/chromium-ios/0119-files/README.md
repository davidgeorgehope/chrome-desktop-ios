Phone trackpad for the iOS Views BrowserView

Apply after 0118. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
New chrome/browser/ui/views/ios/views_trackpad_ios.{h,mm}: ChromeViewsIOSTrackpadView, added to the phone scene by chrome_views_ios_main.mm and shown only while an external scene is connected. One-finger pan moves a cursor overlay window on the TVOut scene (gain 2.5); tap is a left click, two-finger tap a right click, two-finger pan a scroll (gain 3). Hit-testing walks widget windows on the external scene front to back: over a RenderWidgetUIView it injects mouse/wheel into Blink, otherwise it dispatches ui::MouseEvent/MouseWheelEvent through NativeWidgetIOS. UIKeyInput insertText/deleteBackward and pressesBegan (arrows, Esc, Cmd shortcuts) become ui::KeyEvents to the focused widget or web view. A keyboard button toggles the soft keyboard (empty inputView otherwise). BUILD.gn adds the sources and deps. Debug NSLogs remain; trimmed later.

Status (19 Nov 2026, 11:27 AM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
