Give NativeWidgetIOS a valid LocalSurfaceId and pixel-sized SetScaleAndSize.

The Milestone 1 host placed a widget window on the Simulator, but
SetScaleAndSize was called with DIP size and an empty
viz::LocalSurfaceId(), which is not enough for the compositor to
present. Match BrowserCompositorIOS: allocate IDs with
ParentLocalSurfaceIdAllocator and pass gfx::ScaleToCeiledSize.

After this, the widget is still the UIKit content-view background
(0.13, 0.14, 0.16), not the red Views Label. A follow-up needs the
Simulator to present DisplayCALayerTree frames; subclassing
CALayerFrameSinkProvider as UIView instead of
BELayerHierarchyHostingView is the leading hypothesis, but doing
that on the shared provider breaks
image_transport_surface_overlay_mac.mm (it uses the BELayer .handle).
The next step is a Views-only UIView hosting path, then place the
widget on Simulator TVOut.

Apply `../0020-ios-views-compositor-local-surface-id.patch` after 0017.
