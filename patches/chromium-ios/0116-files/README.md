iOS Views: re-enable PartitionAllocSchedulerLoopQuarantine

Apply after 0115. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
chrome_views_ios_main.mm no longer appends PartitionAllocSchedulerLoopQuarantine to --disable-features. The OOM trap it was hiding came from the infinite recursion in BrowserView::GetAccessibleWindowTitle (fixed in 0108). Verified with several TVOut runs (example.com, UA echo, google.com) with no crash.

Status (19 Nov 2026, 10:55 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
