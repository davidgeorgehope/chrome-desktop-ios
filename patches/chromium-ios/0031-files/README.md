Views M2 compile: start the C++ / resource build of
//chrome/browser/ui/views/frame:browser_view on iOS behind
enable_ios_desktop_views.

Apply after 0030. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. Do not treat the 0026
look-alike shell as BrowserView, and do not build further on it.

What this patch does
--------------------
- Skip native iOS Chrome locale remaps (es-MX / pt) when the desktop
  Views flag is on, so grit expected pak lists match desktop grd
  names (es-419 / pt-BR).
- Use grit -t darwin and Mac title case for desktop Views on iOS, so
  grd is_ios filename branches emit desktop pak names and Mac string
  selection is used.
- Use locale_settings_mac.grd for platform locale settings.
- Include chrome_send TypeScript typings and the default (non-iOS)
  ts_library platform for desktop WebUI.
- Generate searchbox.mojom on iOS when the flag is on, so composebox
  mojom imports resolve.

Status (18 Nov 2026, 10:12 PM ET)
--------------------------------
gn gen remains green. Compile of browser_view_ios is in progress;
this is not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
Device args.gn stays without enable_ios_desktop_views.
