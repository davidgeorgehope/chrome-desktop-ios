iOS Views: trim bring-up diagnostics

Apply after 0127. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Removes the temporary diagnostics added during M1/M2 bring-up (0107, 0113 and the viz/gpu presenter work): per-frame logs in SkiaRenderer::ScheduleOverlays, SkiaOutputSurfaceImplOnGpu::PresentFrame, SkiaOutputDeviceBufferQueue::DoFinishSwapBuffers, OverlayProcessorMac::ProcessForOverlays, DisplayCALayerTree::UpdateCALayerTree, presenter Present/ScheduleCALayer and the sink-chain walk, CommitPresentedFrameToCA and its CALayer tree dump; NativeWidgetIOS layer/View tree dumps, window placement, SetAcceleratedWidget, OnPaintLayer and key logging; NativeViewHostIOS frame logs; trackpad scroll/insertText/becomeFirstResponder logs and the window audit. The four viz/display files return to upstream. Functional behaviour is unchanged: the empty-candidate CA fallback, CATransaction flush and delayed ScheduleDraw remain. Kept one-line lifecycle logs (scene willConnect, attached compositor root, No CALayer host, trackpad attached/click/cursor) that the test scripts parse. Startup now prints 7 DeskBrowser lines. Verified Wikipedia renders at 1912 px with the Mac UA.

Status (19 Nov 2026, 12:41 PM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
