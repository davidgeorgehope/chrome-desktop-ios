Fix history side panel mojom deps and iOS native messaging build.

Apply after 0044. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
The history and history-clusters side panel headers include history_clusters.mojom.h; depend on its mojo bindings directly. Hide the unused native-messaging manifest lookup helper on iOS.

Status (19 Nov 2026, 12:20 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
