Fix fourth batch of iOS Views browser compile errors

Apply after 0059. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Fresh errors from the 02:52 AM ET compile:
- security_interstitials/content, open_from_clipboard and the common syncable prefs table follow desktop branches (IOS_MOBILE_UI), matching security_interstitials/core and translate.
- bookmarks drag data: the IS_IOS && TOOLKIT_VIEWS pickle path is restored (the earlier rewrite turned it into IOS_MOBILE_UI).
- flags: iOS Views reports kOsMac.
- translate bubble: the iOS-only never-translate step is IOS_MOBILE_UI.
- chrome/browser core deps add the on-device translation internals and history sync opt-in mojo bindings for iOS Views without pulling the Win/Mac/Linux updater and app-settings set.
- web_authentication_proxy extension schema is generated for iOS Views.
- PDF user education promos and includes require ENABLE_PDF; certificate manager prefs require CHROME_ROOT_STORE_CERT_MANAGEMENT_UI.
- report-unsafe-site screenshot limits come from ClientSideDetectionHost only with full Safe Browsing.
- settings language/autofill strings use IS_APPLE to match darwin grit output.
- crash product name Chrome_iOS; aura include only with USE_AURA; IsForceSaveToCloud maybe_unused.
- desktopize.py keeps IS_IOS in positive Mac lists and TOOLKIT_VIEWS conditions; walk-gn-asserts.py takes WALK_ROOT.

Status (19 Nov 2026, 3:14 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
