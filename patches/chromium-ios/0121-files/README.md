Trackpad: log two-finger scroll begin/end

Apply after 0120. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Debug NSLog in ChromeViewsIOSTrackpadView handleScroll for non-Changed states (delta, hit view class). Also adds the simulator-only AXe/CDP trackpad test helpers under tools/ios-views-trackpad (omnibox nav, scroll, closed-loop cursor goto, YouTube search). Scroll verified on Wikipedia (scrollY 0 -> 570 -> 0).

Status (19 Nov 2026, 11:41 AM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
