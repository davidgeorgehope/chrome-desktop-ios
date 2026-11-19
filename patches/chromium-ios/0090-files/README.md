Enable message center notifications on iOS Views

Apply after 0089. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Launch hit CHECK(message_center_bridge_) in NotificationPlatformBridgeDelegator: with no system bridge, desktop Chrome needs the message center. enable_message_center and enable_chrome_notifications now include iOS Views. Ports: message_popup_view_ios.mm (opacity from UIWindow alpha, which NativeWidgetIOS::SetOpacity sets) and fullscreen_ios.mm. Host build and link succeed.

Status (19 Nov 2026, 7:41 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
