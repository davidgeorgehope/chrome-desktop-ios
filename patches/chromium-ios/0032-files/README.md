Views M2 compile: continue the C++ / WebUI build of
//chrome/browser/ui/views/frame:browser_view on iOS behind
enable_ios_desktop_views.

Apply after 0031. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. Do not treat the 0026
look-alike shell as BrowserView, and do not build further on it.

What this patch does
--------------------
- Adds BUILDFLAG(ENABLE_IOS_DESKTOP_VIEWS) to //build:ios_buildflags.
  Native iOS Chrome UI string/program paths that need is_ios-only
  grit messages are skipped when the flag is on, so those files
  follow the desktop branch (grit is invoked with -t darwin).
- Includes the desktop cr_elements / js TypeScript sources
  (i18n_mixin_lit and friends) when the flag is on.

Status (18 Nov 2026, 10:28 PM ET)
--------------------------------
Compile of browser_view_ios is in progress past 2000 successful
steps. This is not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
Device args.gn stays without enable_ios_desktop_views.
