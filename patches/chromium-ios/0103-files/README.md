Register the iOS 27 external-display accessory for iOS Views

Apply after 0102. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
ChromeViewsIOSSceneDelegate registers an externalNonInteractive UISceneAccessory on the phone scene's root view controller (iOS 27 does not connect the external scene from Info.plist alone). External scenes get a backing window below the browser widgets. On the iOS 27 simulator the TVOut scene connects (1920x1080) and NativeWidgetIOS moves the Chrome window there; the TVOut screenshot now shows the app's own compositor output rather than a mirror.

Status (19 Nov 2026, 8:52 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
