iOS Views: use UIKit system font for dot-prefixed font names

Apply after 0109. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
PlatformFontIOS::GetCTFont: on iOS 13+ fontWithName:@".SFUI-Regular" returns TimesNewRomanPSMT (CoreText logs this). For ENABLE_IOS_DESKTOP_VIEWS, dot-prefixed names now map to [UIFont systemFontOfSize:weight:] with the gfx weight mapped to UIFontWeight, plus the italic trait when needed.

Status (19 Nov 2026, 10:11 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
