Cut default browser prompt, scheduled restart, WhatsNew, session restore infobar on iOS

Apply after 0078. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Narrowed the earlier bulk ENABLE_IOS_DESKTOP_VIEWS widening back to Win/Mac/Linux for scheduled restart (app menu item and icon, action, command, bubble, NTP nudge, local state prefs), WhatsNew startup fetch and prefs, session restore infobar (controller, infobar registry, infobar internals), desktop shortcut action. Added !IS_IOS for the default browser prompt (startup infobar, app menu item, set-as-default action, prompt prefs) and the settings default browser / manage profile / system handlers. infobar internals returns false for the cut types. browser_prefs.cc also carries the FirstRunService prefs cut used by 0081. Host link (with 0080): 204 -> 146 undefined symbols.

Status (19 Nov 2026, 6:35 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
