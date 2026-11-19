Use software client certificate keys on iOS Views

Apply after 0090. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Launch hit crypto/apple/unexportable_key_apple.mm CHECK(!keychain_access_group.empty()) from CertificateStoreFactory. iOS Views has no keychain access group, so skip the unexportable key factory there and keep software keys.

Status (19 Nov 2026, 7:45 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
