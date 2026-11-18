Updated Blink Chrome sources for patch 0011 (external display).

When an external display is connected, Chrome registers the iOS 27
UISceneAccessory.externalNonInteractive accessory (and declares
UIWindowSceneSessionRoleExternalDisplayNonInteractive in Info.plist
for iOS 16–26) and creates a fullscreen window on that scene. The
hosted Chrome UI is forced into the iPad / regular x regular size
class so the tab strip and full top toolbar appear, even on an
iPhone. The phone screen becomes a control surface.

iPhone iOS 27 does not offer Stage Manager or an interactive
external-display scene role. Real desktop Views/Aura chrome is not
available on iOS. iOS Chrome has no bookmarks bar to show.

Copy these paths over `chromium/src/` after patches 0001-0010, or
apply `../0011-ios-external-display-desktop-chrome.patch`.
