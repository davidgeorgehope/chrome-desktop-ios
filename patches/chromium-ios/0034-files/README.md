Views M2 compile: include iOS-only grit IDs that share a
then/else with desktop names, plus the NTP footer TypeScript
deps, without enabling enable_webui_ntp.

Apply after 0033. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. Do not treat the 0026
look-alike shell as BrowserView, and do not build further on it.

What this patch does
--------------------
- Flatten disjoint then/else is_ios message blocks so both the iOS
  and desktop IDs are emitted when the flag is on (needed by C++ that
  still compiles under BUILDFLAG(IS_IOS)).
- Emit unique iOS/Android-only scaled image structures (including
  IDR_INFOBAR_AUTOFILL_CC) when the flag is on.
- Give new_tab_footer its customize_buttons / new_tab_shared
  TypeScript and mojo typings when the flag is on, without turning on
  enable_webui_ntp or enable_extensions_core. C++ in
  customize_buttons stays gated on enable_webui_ntp.

Status (18 Nov 2026, 10:54 PM ET)
--------------------------------
gn gen remains green (45004 targets). Compile of browser_view_ios
has been restarted. This is not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
Device args.gn stays without enable_ios_desktop_views.
