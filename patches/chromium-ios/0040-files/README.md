Build desktop Views on iOS with extensions and guest_view on.

Apply after 0039. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
The real BrowserView graph assumes the full desktop extensions system (web_app_install_info, extension_ui_util, web_applications/extensions, etc. all require it). Follow Mac and set enable_extensions = true and enable_guest_view = true in the Simulator Views args (scripts/chromium-ios/args-views-simulator.gn). The walker gated test-only deps that iOS cannot build (chrome/test, print preview, webui NTP), retargeted //chrome:resources to leaves, and the devtools pak is listed only when enable_devtools_frontend is set. gn gen is green for browser_view_ios with these args.

Status (18 Nov 2026, 11:51 PM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
