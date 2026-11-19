Re-home iOS Views widgets when a scene connects

Apply after 0101. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Chrome creates its BrowserView widget in willFinishLaunching, before UIKit connects a UIWindowScene, so its UIWindow had no scene and never appeared. NativeWidgetIOS now observes UISceneWillConnect/DidActivate and moves every widget window to PreferredWindowScene() (external display first) via a new MoveToPreferredScene(), which Show() also uses. Verified on the iOS 27 simulator: the windows join the phone scene and lay out.

Status (19 Nov 2026, 8:48 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
