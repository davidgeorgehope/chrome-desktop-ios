Cut profile picker and desktop-only WebUIs on iOS Views

Apply after 0077. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
ProfilePicker on iOS: shared profile_picker.cc (Params, startup mode forced to browser window) plus profile_picker_ios.cc with no-op window statics. Narrowed WebUI configs and interface binders on iOS: default browser modal, profile picker, profile customization, managed user notice, WhatsNew, web app settings, on-device translation internals, history sync opt-in, chrome://apps. default_browser_modal source_set removed from the iOS graph (mojom headers kept). Host link: 233 -> 204 undefined symbols. Cut list updated in docs/desktop-chrome-ios-plan.md.

Status (19 Nov 2026, 6:27 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
