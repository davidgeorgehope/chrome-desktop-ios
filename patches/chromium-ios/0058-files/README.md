Fix third batch of iOS Views chrome/browser platform gates

Apply after 0057. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Platform-gate fixes in chrome/ from the 02:49 AM ET compile:
- crash reporter client: client-ID override is !IS_APPLE, crashpad socket handling is not used on iOS.
- missing-locale message box, WebUI location bar width, and zygote lookup take the Mac (IS_APPLE) path.
- profile network context: iOS uses the empty platform client cert store wrapped with profile/browser stores, as on Android.
- QWAC verification (tab features, page info, about:flags) is compiled only with CHROME_ROOT_STORE_SUPPORTED; the root store feedback log source is built only then too.
- about:flags: PDF Glic summarize needs ENABLE_PDF; the desktop scam-detection model flag is not offered on iOS.
- enterprise sign-in service and the web authentication proxy API accept ENABLE_IOS_DESKTOP_VIEWS.
- FullscreenAllowed policy mapping follows the Apple policy list; desktop media picker registers native windows only on Aura/Mac.
- explicit blink::StorageKey include; unused captive portal field is maybe_unused.
- history: browsing-history-by-actor feature uses IOS_MOBILE_UI.
- data protection unit test needing cloud content scanning is gated on enterprise_cloud_content_analysis.

Status (19 Nov 2026, 2:54 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
