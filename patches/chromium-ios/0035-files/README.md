Views M2 compile: enable the Views bookmark drag pickle
path and BookmarkEntriesType on iOS desktop Views.

Apply after 0034. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. Do not treat the 0026
look-alike shell as BrowserView, and do not build further on it.

What this patch does
--------------------
- Declare and implement ClipboardFormatType::BookmarkEntriesType() on
  iOS, using the same Chromium bookmark UTI as Mac.
- Compile the non-Apple pickle read/write path on iOS when
  TOOLKIT_VIEWS is defined, so bookmark_node_data_views.cc can build.
  Native iOS clipboard stubs in bookmark_node_data_ios.cc are
  unchanged.

Status (18 Nov 2026, 11:00 PM ET)
--------------------------------
gn gen remains green. The bookmark Views objects compile. Full
compile of browser_view_ios has been restarted. This is not
BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
Device args.gn stays without enable_ios_desktop_views.
