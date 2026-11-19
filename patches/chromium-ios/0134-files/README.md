iOS Views app: desktop windows only on the monitor; phone shows connect hint

Apply after 0133. Used by the separate desktop Views app
(com.davidhope.deskbrowser.chromeviews, out/Release-iphoneos-views and the
simulator). The existing Chromium.app device build keeps
enable_ios_desktop_views off.

What this patch does
--------------------
NativeWidgetIOS::SetRequireExternalDisplay(true) (called by chrome_views_ios_main.mm before ContentMain) makes PreferredWindowScene return only the external-display scene, so desktop Chrome widgets never fall back onto the phone screen (cold launch without a monitor previously drew a small BrowserView over the phone). Default stays false so views_examples is unchanged. The phone trackpad view is no longer hidden without a monitor: it shows "Connect a monitor to use desktop Chrome" and disables input/keyboard until an external scene exists, then switches to the trackpad hint. Verified in the simulator (2:19–2:21 PM ET): cold launch with no monitor shows only the connect hint on the phone; TVOut plug shows BrowserView (example.com) on the monitor and the trackpad on the phone; unplug returns the hint; replug restores BrowserView; app alive throughout.

Status (19 Nov 2026, 2:18 PM ET)
--------------------------------
Phase A device build in progress (docs/device-build-plan.md).

Replace the listed files with the copies in this directory.
