Infobar internals and updater binder gates for iOS Views

Apply after 0062. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
- infobar_internals.mojom: the default-browser, link-capturing and session-restore infobar types are also enabled by a new ios_desktop_views mojom feature (set only for iOS Views), matching the widened C++ handler, instead of treating the whole mojom as Mac (which added Keystone/PDF/taskbar types).
- WebUI interface binders: the updater page binder and its includes stay Win/Mac/Linux only.

Status (19 Nov 2026, 3:40 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
