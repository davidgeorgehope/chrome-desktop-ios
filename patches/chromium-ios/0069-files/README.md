Mac-parity startup faults, CPU info, display info, proxy observer

Apply after 0068. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Use the mach hard-fault counter on iOS Views, skip the Rosetta-only check in the shared Mac CPU provider, build Mac's no-op display info provider and the proxy override modifiability observer.

Status (19 Nov 2026, 4:38 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
