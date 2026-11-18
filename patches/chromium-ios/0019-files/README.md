Register the iOS 27 external-display scene accessory on a real presenter.

David's 0012 monitor test still showed system mirroring, and
get-display-info listed the Dopesplay as TVOut 1920x1080 with
backlight off and bounds 0x0. The 0012 syslog never logged
"registered iOS 27 scene accessory" or an isAvailable value:
RegisterAccessoryIfPossible() returned silently because it could
not find a presenter UIViewController whose view was in a window.

This is expected on iOS 27 when the accessory is not registered:
UIKit keeps system mirroring, does not connect a
UIWindowSceneSessionRoleExternalDisplayNonInteractive scene, and
does not expose a second UIScreen or UIScreen.mirroredScreen
(screens=1, mirrored=N). There is no extra entitlement or Info.plist
key; Apple's docs (Presenting content on a connected display /
scene-based life cycle, iOS 27) require
UISceneAccessory.externalNonInteractive(sceneConfiguration:)
registered on a view controller in the main interface, with the
registration retained. The Info.plist role alone is ignored.
The UIScreen.mirroredScreen fallback cannot work until UIKit
exposes that screen, which it will not do while it is still
mirroring. The Dopesplay is a USB-C DP alt-mode monitor (core-device
productName/TVOut), not AirPlay.

This patch:
- Compares UISceneSessionRole with isEqualToString: (pointer == / !=
  on NSString can miss the application window).
- Walks every scene window, force-loads the root / child VCs, and
  logs why registration was skipped instead of failing silently.

Apply `../0019-ios-external-display-accessory-presenter.patch` after
0012 (it only touches deskbrowser_external_display.mm).
