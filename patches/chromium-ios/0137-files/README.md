iOS Views: follow external screen mode changes

Apply after 0136. Used by the desktop Views app (chrome_views_ios,
out/Release-iphoneos-views and the simulator). The ios/chrome Chromium.app
device build keeps enable_ios_desktop_views off.

What this patch does
--------------------
The browser window was sized to the external screen only when it moved to that scene. A screen can change size while its scene stays connected: an AirPlay receiver renegotiating its mode, or a TV switching resolution. The scene delegate now implements windowScene:didUpdateCoordinateSpace:interfaceOrientation:traitCollection: for non-phone scenes and calls NativeWidgetIOS::ExternalSceneGeometryChanged(), which re-runs MoveToPreferredScene for every widget. MoveToPreferredScene refits maximized top-level windows whenever the screen size differs, not only on a scene change. display::Screen (screen_ios.mm) refreshes on UIScreenModeDidChangeNotification and on the geometry change. AirPlay Screen Mirroring and wired displays use the same path (external UIScreen, UIWindowSceneSessionRoleExternalDisplayNonInteractive, UISceneAccessory registration), so nothing in the code assumes a cable. Simulator check: TVOut 1920x1080 → 1280x720 → 1920x1080 while connected; BrowserView refits each time and the app stays alive. Real AirPlay is not available in the simulator.

Replace the listed files with the copies in this directory.
