Fix the iOS 27 external-display blank window, Back CHECK, and pointer.

David's 0018+0019 field test (build b1384cb9, 5:37 PM ET) took over the
monitor (available=1, mirrored=N, official ExternalDisplayNonInteractive
scene) but the external window was blank, the hardware pointer stayed on
the phone, and Back on the camera test page crashed Chrome.

The Back abort is a CHECK, not a DCHECK: RenderWidgetUIView's
accessibilityElements operator->'d an invalidated WeakPtr to
RenderWidgetHostViewIOS after navigation destroyed the host
(weak_ptr.h:277, _UIAXBroadcastMainThread, 5:33:59 PM ET).

The blank window came from two races:

1. AttachLegacyWindowIfMirroring / UIScreen takeover ran first (legacy=1
   at 5:34:44.518), 25 CoreAnimation "cannot add handler to 0 from 0"
   errors followed, then the official scene connected 132ms later. After
   official disconnect, the legacy path immediately re-claimed the
   screen.
2. Moving the Chrome SceneViewController / BELayerHierarchyHostingView
   to a new window without re-assigning BELayerHierarchyHandle left a
   blank surface.

This patch:

- Guards accessibilityElements, layoutSubviews, and becomeFirstResponder
  on a live WeakPtr / host (and returns nil / super instead of CHECK).
- Drops the legacy UIScreen / mirroredScreen takeover. AttachTimerTick
  only Places Chrome when an official ExternalDisplay or
  ExternalDisplayNonInteractive scene window exists. Official disconnect
  restores Chrome to the phone and does not re-claim UIScreen.
- Re-binds the BELayer hierarchy in didMoveToWindow and after PlaceChrome
  (immediate plus a 0.15s second pass) so the compositor has a non-zero
  render-server context.
- Turns the phone into a trackpad for the external Chrome window: cursor
  overlay, one-finger move, tap to click, two-finger scroll, and
  keyboard presses forwarded at the hosted RenderWidgetUIView.

Apply after 0019. Device IPA: Views flag off, jitless default. Does not
include the uncommitted Views M1 (0021) UIView-host work.
