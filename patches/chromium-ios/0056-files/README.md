Desktopize autofill, omnibox and bookmarks for the Chrome libs build.

Apply after 0055. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Fix further C++ compile failures. Desktopize components/autofill/core, components/omnibox/browser and components/bookmarks. Add iOS Views to the contextual_tasks_private extension schema. Guard unsafe-site reporting behind SAFE_BROWSING_AVAILABLE. Widen wasm TTS auto-install flags for iOS Views; use Mach port provider for process priority on Blink iOS. Fix the no-printing context-menu path; match spellcheck strings to darwin grit. Version history uses the Mac arm64 platform. Fix unused helpers, add UIWindow ordering for tab dragging, and use a no-op iOS app-modal event blocker (there is one external browser surface). ECSigningKey's GetSecKeyRef override uses IS_APPLE to match the interface. Turn on on-device translation in simulator args for live caption Mac parity.

Status (19 Nov 2026, 2:45 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
