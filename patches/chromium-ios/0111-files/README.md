iOS: attach in-process GPU surfaces directly, below native subviews

Apply after 0110. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
ImageTransportSurfaceOverlayMacEGL host attach: when the GPU runs in the browser process (--in-process-gpu or --single-process) nothing hosts a BELayerHierarchy handle, so RenderWidgetHostViewIOS surfaces never displayed. Skip the BELayerHierarchy path in that case and parent the compositor root CALayer on the sink/host layer directly, inserted at index 0 so native subviews (NativeViewHostIOS UIViews) stay above it. Result: example.com renders on TVOut.

Status (19 Nov 2026, 10:23 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
