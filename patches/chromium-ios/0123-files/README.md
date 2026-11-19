chrome_views_ios Info.plist: microphone and camera usage descriptions

Apply after 0122. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Adds NSMicrophoneUsageDescription and NSCameraUsageDescription to the chrome_views_ios app plist, matching content_shell's ios-app.plist, so a site's getUserMedia gets the system permission prompt instead of the TCC privacy kill. Also adds tools/ios-views-trackpad/tp-video.sh (simulator-only YouTube playback probe).

Status (19 Nov 2026, 11:58 AM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
