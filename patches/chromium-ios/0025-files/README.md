Views Milestone 1: red "DeskBrowser Views M1" label paints on the
iOS 27 Simulator TVOut (1920x1080 official external scene).

Apply after 0020 (Views host) and 0024 (unrelated device omnibox fix).
This does not go into the device IPA; keep enable_ios_desktop_views
off for device builds.

What was wrong
--------------
The compositor did Present and CommitPresentedFrameToCA (1110x780,
then 1920x1080), but the committed CA tree was only the CARenderer
0x0 root wrapper: no content layers, no IOSurfaces. CALayerParams
never reached DisplayCALayerTree because on iOS
EnsureCAContextAndRootLayer skips CAContext creation, so
params.ca_context_id is 0 and IsEmpty() is true; Skia drops them.

The deeper cause of the empty tree was that NativeWidgetIOS::SetBounds
never called Widget::OnNativeWidgetSizeChanged. On Mac, AppKit does
that callback; on iOS nothing did, so RootView stayed 0x0, OnPaint
drew nothing, OverlayProcessorMac "succeeded" at promoting 0 quads
to 0 CA layers, and damage was cleared so later frames never appeared.

The official iOS 27 TVOut scene does connect once
UISceneAccessory.externalNonInteractive is registered and
configurationForConnectingSceneSession is implemented. TVOut
screenshots that were ~38736 bytes were a solid UIColor 0.13
gray (the host UIView), not an uncomposited framebuffer.

What this patch does
--------------------
- NativeWidgetIOS::SetBounds/SetSize notify OnNativeWidgetSizeChanged
  whenever RootView's size does not match the window, including the
  first same-size SetBounds during init (RootView starts at 0x0).
- After placing the widget on the official external scene, schedule
  paint; set the host layer contentsScale from the window's screen.
- Skip the CAContext path on iOS: attach coordinator->root_ca_layer()
  directly as a sublayer of the unowned Views host
  (RegisterUnownedHostCALayer / high-bit handles) so the committed
  CA tree is visible without DisplayCALayerTree.
- If CA overlay promotion "succeeds" with zero candidates, fall back
  to the primary plane instead of clearing damage.
- Overlay constructor no longer dispatch_syncs the main queue
  (deadlock). MessagePump is attached after UIApplicationMain.
- views_examples_ios registers the iOS 27 official external accessory,
  places the widget fullscreen on TVOut, and shows a red MilestoneView
  (SkColor 0xC81D25, label "DeskBrowser Views M1").

Verified 7:49 PM ET on the iOS 27.2 iPhone Duo simulator
(UDID DE1E2D59-E674-4EE1-8096-097886FB5917), hinge 180, TVOut
1920x1080: 14-tvout.png is 1920x1080 with 2,071,396 pixels of
exact 0xC81D25 and 574 white label pixels. The inner LCD is
dark because the widget moved to the official external scene.

Replace the listed files with the copies under ui/, gpu/, and
components/ in this directory (they are complete current sources).
