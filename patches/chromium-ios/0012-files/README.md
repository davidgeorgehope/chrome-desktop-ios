Updated Blink Chrome sources for patch 0012 (external-display
mirroring takeover).

On a real iPhone + monitor, iOS 27 kept mirroring the phone UI
because the app never took over the display with its own scene.
Info.plist already declared
UIApplicationSupportsMultipleScenes and
UIWindowSceneSessionRoleExternalDisplayNonInteractive with
DeskBrowserExternalDisplaySceneDelegate (patch 0011). That is
enough on the iOS 26 Simulator, but not on iOS 27: the system
ignores the plist role unless a UISceneAccessory is successfully
registered, and MainApplicationDelegate did not implement
configurationForConnectingSceneSession.

This patch:

- Re-registers the iOS 27 externalNonInteractive accessory when
  the presenter view controller changes, and logs isAvailable.
- Implements application:configurationForConnectingSceneSession:
  so UIKit can instantiate DeskBrowserExternalDisplaySceneDelegate.
- If no official external scene appears, places a UIWindow on
  UIScreen.mirroredScreen / a second UIScreen (Apple: this disables
  mirroring) and hosts Chrome there.

Copy these paths over `chromium/src/` after patches 0001-0011, or
apply `../0012-ios-external-display-mirroring-takeover.patch`.
The Info.plist from 0011 is unchanged.
