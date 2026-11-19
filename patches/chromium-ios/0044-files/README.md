Enable Dice account consistency for desktop Views on iOS.

Apply after 0043. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Mac uses Dice, so enable_dice_support now includes is_ios && enable_ios_desktop_views (the desktop token service delegate is chosen instead of the iOS one). Desktopizes the user cloud signin restriction fetcher, keeps the Win/Mac-only download backoff feature unwidened, and gates chrome/test test_support deps in signin BUILD files.

Status (19 Nov 2026, 12:19 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
