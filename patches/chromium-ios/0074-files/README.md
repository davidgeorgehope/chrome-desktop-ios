iOS Views process singleton, memory details, downloads, policy throttle

Apply after 0073. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
UIKit enforces one app instance: process_singleton_ios.cc. Single-process memory_details_ios.cc, no-op download drag and dock progress. Build the policy blocklist throttle, profile cloud policy manager and enterprise NTP shortcuts as on Mac. Keep What's New, chrome://apps, scheduled restart, default browser prompts and Gapis off on iOS.

Status (19 Nov 2026, 5:39 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
