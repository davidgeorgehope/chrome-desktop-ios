iOS: guard ImageTransportSurfaceOverlayMacEGL main-queue block against UAF

Apply after 0108. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
The constructor's dispatch_async(main) block that attaches the compositor CALayer to its host captured a raw this. When the surface was destroyed before the block ran (frame sinks are recreated on navigation) it wrote freed memory (SEGV_ACCERR 0xcdcdcdcd...). The block now holds a scoped_refptr to a RefCountedThreadSafe MainQueueGuard {Lock, raw_ptr overlay}; the destructor nulls overlay under the lock and the block returns early.

Status (19 Nov 2026, 10:11 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
