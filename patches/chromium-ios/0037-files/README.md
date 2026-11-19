Views M2 compile: only list kChromeUIWhatsNewHost in the
chrome://chrome-urls table on Win/Mac/Linux, matching the header.

Apply after 0036. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. Do not treat the 0026
look-alike shell as BrowserView, and do not build further on it.

What this patch does
--------------------
- The debug host list used kChromeUIWhatsNewHost under !Android &&
  !ChromeOS, but the constant is only declared on Win/Mac/Linux. Align
  the list with the declaration so iOS desktop Views can compile.

Status (18 Nov 2026, 11:27 PM ET)
--------------------------------
webui_url_constants.o compiles. Full compile of browser_view_ios has
been restarted. This is not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
Device args.gn stays without enable_ios_desktop_views.
