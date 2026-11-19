Fix the first chrome/browser, renderer and utility compile errors on iOS Views.

Apply after 0054. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Desktopize security_interstitials/core (fixes ShowCertificateViewer), browsing_data/core, collaboration_service_impl.cc and the save-and-fill dialog controller header. Turn on enable_screen_ai_service for Mac parity: utility and renderer include screen_ai mojoms, and the OCR strings sit behind that flag. Guard SAFE_BROWSING_AVAILABLE in download obfuscation, ENABLE_PRINTING in browser_web_contents_delegate (its dep on components/printing/browser is now conditional) and CHROME_ROOT_STORE_SUPPORTED in pki_metadata. No desktop dir or captive portal login tab on iOS. The Firefox importer skips NSS on all Apple platforms. Build the Aura tab drag adapter only with use_aura. GetSupportedKeySystems fallback calls the two-arg callback. read_anything compiles without PDF.

Status (19 Nov 2026, 2:38 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
