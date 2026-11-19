Port bookmark clipboard, app exit, frame view; cut small desktop-only callers on iOS Views

Apply after 0082. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Ports: BookmarkNodeData clipboard through ui::Clipboard (iOS impl exists); application_lifetime_ios.mm; GetDirectLaunchUrlScheme (empty) in the shared shell_integration_android.cc; opaque_browser_frame_view_impl linked into browser_frame_view_factory_ios. Stubs/cuts: notification_platform_bridge_ios.cc (message center only), PiP stub occlusion helper, version_updater_basic, feedback-disabled dialog, policy_ui command line, settings System strings, delete profile on sign out. Host link: 92 -> 79 undefined symbols.

Status (19 Nov 2026, 6:48 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
