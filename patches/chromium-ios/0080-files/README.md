Cut desktop-only policy handlers and platform provider on iOS Views

Apply after 0079. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
configuration_policy_handler_list_factory.cc: narrowed browser switcher, enterprise skills, memory saver / search aggregator / site search, guest mode / local sync / theme color, Gemini URL blocks back to their desktop platforms; battery saver !IS_IOS. ChromeBrowserPolicyConnector::CreatePlatformProvider returns null on iOS (no config dir loader). Built the platform-neutral proxy and proxy override rules policy handlers (components/proxy_config) and cookie settings policy handler (content_settings, use_blink) for iOS Views.

Status (19 Nov 2026, 6:35 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
