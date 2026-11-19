Fix sixth batch of iOS Views browser compile errors

Apply after 0061. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
From the 03:15 AM ET compile:
- Interstitial commands mojom uses Mac features on iOS Views so the certificate viewer command exists; date/time settings on iOS stay NOTIMPLEMENTED like Fuchsia.
- Enterprise cloud management uses an unenrolled iOS DM token storage delegate (empty tokens, no saves).
- WebUI configs register app settings, browser switch, updater, history sync opt-in, on-device translation internals and What's New only on Win/Mac/Linux; those page targets are not built for iOS Views.
- Read Anything's PDF frame lookup is compiled only with PDF; compose_enabling.h is guarded by components/compose/buildflags.h.
- Unreachable break and unused picker flag warnings fixed.

Status (19 Nov 2026, 3:33 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
