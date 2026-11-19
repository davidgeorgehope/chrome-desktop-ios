Desktopize enterprise, tab groups, translate and autofill content; restore positive platform lists

Apply after 0056. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Switches components/enterprise, components/saved_tab_groups, components/translate/core, components/autofill/content and components/webui/{flags,version} from IS_IOS to IOS_MOBILE_UI branches so they match the desktop Chrome callers. components/enterprise/buildflags/buildflags.gni is left at upstream.

Widens the passkey unlock error UI features (device/fido) and the can_submit_feedback capability to ENABLE_IOS_DESKTOP_VIEWS.

The earlier IS_IOS -> IOS_MOBILE_UI pass also rewrote 43 positive Mac/Win/Linux/iOS lists (autofill prefs and payments, password manager prefs and store, enterprise proxy policy, signin capabilities). Those lists include Mac, so the desktop build belongs in them; they are restored to IS_IOS.

Status (19 Nov 2026, 2:51 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
