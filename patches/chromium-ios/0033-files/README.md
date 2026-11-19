Views M2 compile: emit iOS-only grit message IDs under
enable_ios_desktop_views when grit is invoked with -t darwin.

Apply after 0032. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. Do not treat the 0026
look-alike shell as BrowserView, and do not build further on it.

What this patch does
--------------------
- Always pass -D enable_ios_desktop_views=${enable_ios_desktop_views}
  to grit so grd/grdp expressions can test the flag on every platform.
- Expand message-only positive is_ios conditions for IDs that have no
  desktop counterpart, so -t darwin still emits them. Leave then/else
  and not-is_ios branches alone so desktop strings are not duplicated
  or replaced with iOS wording.

Status (18 Nov 2026, 10:46 PM ET)
--------------------------------
gn gen remains green (44977 targets). Compile of browser_view_ios
has been restarted after the previous autofill expiration-date
string-ID failure. This is not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
Device args.gn stays without enable_ios_desktop_views.
