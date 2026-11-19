Run iOS Views Chrome single-process and jitless by default

Apply after 0105. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
chrome_views_ios_main.mm appends --single-process, --in-process-gpu, --js-flags=--jitless and --disable-features=NetTaskScheduler,NetworkServiceTaskScheduler,PartitionAllocSchedulerLoopQuarantine unless already given. The bundle has no BrowserEngineKit child-process extensions, V8 cannot remap builtins into a JIT range without the entitlement, and the PA scheduler-loop quarantine OOM-trapped in BrowserView::GetAccessibleWindowTitle. With these, the real BrowserView tab strip, toolbar and omnibox paint on the iOS 27 simulator TVOut at 1920x1080.

Status (19 Nov 2026, 9:33 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
