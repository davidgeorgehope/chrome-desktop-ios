iOS Views: drive the monitor cursor with a hardware mouse

Apply after 0139. Used by the desktop Views app (chrome_views_ios,
out/Release-iphoneos-views and the simulator). The ios/chrome Chromium.app
device build keeps enable_ios_desktop_views off.

What this patch does
--------------------
The external display scene (UIWindowSceneSessionRoleExternalDisplayNonInteractive) takes no input, and the phone trackpad only handled finger gestures, so a USB or Bluetooth mouse moved the iOS pointer on the phone screen instead of the desktop cursor on the monitor.

- GameController GCMouse: relative motion moves the monitor cursor (not limited by the phone screen edges); left, right and middle buttons send real press, drag and release (web: mousedown/mousemove/mouseup; Views: pressed/dragged/released with double and triple click counts); the wheel scrolls the page or Views under the cursor. Mice connected before or after launch are picked up.
- Phone-side fallback when GameController delivers nothing: hover motion of the iOS pointer over the trackpad moves the cursor, primary and secondary clicks click and right-click, and scroll-wheel pans scroll. These are ignored while GCMouse is active so nothing is doubled.
- The phone root view controller prefers pointer lock, and a UIPointerInteraction hides the iOS pointer over the trackpad.
- Info.plist sets UIApplicationSupportsIndirectInputEvents so mouse clicks arrive as indirect pointer touches; BUILD.gn links GameController.framework.

Simulator check: builds and runs; finger trackpad, taps and keyboard unchanged. A physical mouse is not available in the simulator, so mouse behaviour needs a device check.

Replace the listed files with the copies in this directory.
