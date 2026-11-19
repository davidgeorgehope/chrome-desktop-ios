Restore platform conditions the GN walker dropped from hoisted deps.

Apply after 0038. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
The walker moved some deps into new feature-flag blocks and lost the original platform condition (for example ChromeOS-only document scanner dialogs ended up reachable on iOS). tools/ios-desktop-views/restore-hoisted-dep-conditions.py compares each dep with git HEAD and re-adds ChromeOS/Android/Win/Mac-only conditions that are false on iOS, while keeping the deliberate !is_ios widenings. Also use ts_deps (not deps) for the guest_view TypeScript dep in contextual_tasks, and let the walker take WALK_OUT and walk only the browser_view_ios root.

Status (18 Nov 2026, 11:47 PM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
