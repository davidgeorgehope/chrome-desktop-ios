Build standalone trusted vault; cut webAuthenticationProxy and networkingPrivate on iOS Views

Apply after 0081. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
components/trusted_vault: standalone client/frontend built for iOS Views (Mac parity). webAuthenticationProxy API and networkingPrivate UI delegate narrowed back to Win/Mac/Linux. captive_portal_blocking_page: WiFiService SSID lookup IS_APPLE -> IS_MAC. Host link: 130 -> 92 undefined symbols.

Status (19 Nov 2026, 6:40 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
