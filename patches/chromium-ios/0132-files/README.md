iOS Views app: Chrome Desktop name and launch screen

Apply after 0131. Used by the separate desktop Views app
(com.davidhope.deskbrowser.chromeviews, out/Release-iphoneos-views and the
simulator). The existing Chromium.app device build keeps
enable_ios_desktop_views off.

What this patch does
--------------------
Info.plist for chrome_views_ios: CFBundleDisplayName "Chrome Desktop" so the home-screen icon is distinct from Chromium, and an empty UILaunchScreen dictionary instead of an empty UILaunchStoryboardName (a storyboard name with no storyboard is rejected/letterboxed on device). Bundle ID stays com.davidhope.deskbrowser.chromeviews.

Status (19 Nov 2026, 2:10 PM ET)
--------------------------------
Phase A device build in progress (docs/device-build-plan.md).

Replace the listed files with the copies in this directory.
