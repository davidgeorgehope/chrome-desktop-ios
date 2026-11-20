iOS Views app: home-screen icon

Apply after 0135. Used by the desktop Views app (chrome_views_ios,
out/Release-iphoneos-views and the simulator). The ios/chrome Chromium.app
device build keeps enable_ios_desktop_views off.

What this patch does
--------------------
Adds an AppIcon asset catalog (resources/ChromeDesktopIcons.xcassets) to chrome_views_ios via bundle_data_xcassets. compile_xcassets passes --app-icon AppIcon to actool and merges CFBundleIcons into Info.plist. The icon is the open-source Chromium logo (ios/chrome/app/resources/ChromiumIconsLegacy.xcassets) with a monitor badge, in light, dark and tinted variants, so it is distinct from Chromium.app. Verified in the simulator: Assets.car and CFBundleIcons (CFBundleIconName AppIcon) are in the bundle, and the App Library shows the badged icon.

Replace the listed files with the copies in this directory.
