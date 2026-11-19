iOS Views device reauth, password policies, protocol handlers, os_crypt

Apply after 0070. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Add a no-biometrics device authenticator for iOS Views, build the password cross-domain popup controller and blocklist policy, the protocol handler navigation throttle, and fall back to the POSIX os_crypt key provider (simulator dev host; no Keychain provider yet).

Status (19 Nov 2026, 5:20 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
