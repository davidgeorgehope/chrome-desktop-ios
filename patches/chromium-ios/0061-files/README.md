Fix fifth batch of iOS Views browser compile errors

Apply after 0060. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Errors from the 02:51 AM ET compile not covered by 0058-0060:
- Aura includes in the bookmark editor and picture-in-picture frame view require USE_AURA instead of !IS_MAC.
- Support tool updater collectors stay Win/Mac/Linux only; the updater is not built for iOS.
- File System Access: iOS has no DIR_USER_DESKTOP or DIR_MODULE; desktop requests return an empty path.
- Glic counter-abuse interstitial and the PDF parts of Read Anything are compiled only with Safe Browsing / PDF support; without PDF the distillable-PDF heuristic reports false.
- Infobar internals mojom uses Mac features on iOS Views, matching the C++ handlers.
- Explicit ContentAutofillClient, BrowserDMTokenStorage and ClientCertStoreEmpty includes; compose_enabling.h only with ENABLE_COMPOSE.
- PKI metadata limits and the desktop media picker flag are maybe_unused when their callers are compiled out.

Status (19 Nov 2026, 3:18 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
