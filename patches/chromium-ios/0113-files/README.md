iOS Views: diagnostics for web contents view placement

Apply after 0112. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Temporary logging: NativeViewHostIOS::ShowWidget logs frame changes with the hosted view class, superview and subview index; ImageTransportSurfaceOverlayMacEGL logs the sink UIView superview chain at host attach.

Status (19 Nov 2026, 10:38 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
