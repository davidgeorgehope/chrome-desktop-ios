Build Chrome's WebUI TypeScript for desktop Views on iOS.

Apply after 0052. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Fixes TS compile failures in the chrome libs build. user_education.mojom-webui.ts and version.mojom-webui.ts are now in the shared mojo WebUI set on iOS desktop Views. mojom() takes a new ios_desktop_views_as_mac flag that uses the Mac EnableIf feature set; the policy and cross-device sign-in QR bubble WebUI mojoms set it because their C++ handlers build the Mac paths. Settings TS lists gated on is_mac now use _webui_is_mac, which includes iOS desktop Views, because grit preprocesses as darwin.

Status (19 Nov 2026, 1:40 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
