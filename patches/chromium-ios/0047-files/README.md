Desktopize sync base features; skip windowing hooks on iOS.

Apply after 0046. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
components/sync/base now follows desktop feature declarations (kUnoPhase2FollowUp and friends) under desktop Views. content only declares the Window Management minimize/maximize/restore/resizable delegate hooks off Android and iOS, so BrowserWebContentsDelegate leaves those overrides out on iOS rather than widening //content.

Status (19 Nov 2026, 12:44 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
