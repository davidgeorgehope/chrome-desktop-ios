Repair GN files the walker mis-braced; build omnibox WebUI mojoms.

Apply after 0045. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
An earlier walker pass moved a closing brace so that if (!is_ios) blocks ended up nested inside the previous block. Restores upstream components/crash/core/app, components/feedback and components/services/filesystem BUILD.gn (the copies here are upstream), and rewrites ui/webui/resources/mojo/BUILD.gn from upstream with the omnibox/composebox WebUI mojo TS files enabled for desktop Views, which fixes the composebox TypeScript build.

Status (19 Nov 2026, 12:34 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
