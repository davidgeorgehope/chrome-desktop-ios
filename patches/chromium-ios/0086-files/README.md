Cut cast remoting, signin WebUI dialogs, structured metrics and other desktop callers on iOS Views

Apply after 0085. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Narrowed back to desktop or guarded with IS_IOS / ENABLE_MEDIA_REMOTING: cast remoting in media_router_desktop and cast_mirroring_service_host; HFM security settings toast; multistep filter and wallet tab features; enterprise referrer chain; deprecated apps dialogs; password relaunch and biometric bubbles; history sync opt-in, managed user notice and intercept FRE dialogs (NOTIMPLEMENTED); managed profile disclaimer in DICE interceptor and history sync helper/service; structured metrics; UI DevTools DOM/overlay agents. Host link: 47 -> 11 undefined symbols (+1 duplicate kManagementResources).

Status (19 Nov 2026, 7:02 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
