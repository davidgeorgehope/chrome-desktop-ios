Fix the iOS 27 official-scene connect/disconnect loop and make the
phone trackpad drive native Chrome UI, not just Blink.

0022 registered UISceneAccessory.externalNonInteractive on
SceneViewController, then PlaceChrome moved that VC onto the official
external window. iOS 27 dropped the registration, disconnected the
ExternalDisplayNonInteractive scene, 0022 restored Chrome to the phone,
the accessory became valid again, and the scene reconnected in a tight
150–250 ms loop. TVOut stayed blank.

This follow-up:

- Registers the accessory on a stable 2×2 phone-side host window that
  never leaves the application scene, so PlaceChrome no longer drops
  the registration.
- Clicks, scrolls, and keys no longer require a RenderWidgetUIView.
  NTP and Chrome desktop UI are native UIKit (no render widget until
  a web page loads). The trackpad now hit-tests the external window:
  UIControl sendActions, text-field focus, collection/table select,
  UITapGestureRecognizer invoke, UIScrollView offset, and Blink
  mouse/wheel inject when a RenderWidget is under the cursor.
- Forwards hardware keys to the focused field on the external window
  (OmniboxTextViewIOS). Return inserts "\n" so the omnibox's
  shouldChangeTextInRange path calls textInputShouldReturn (Go).
- Waits for the 1-finger pan recognizer to fail before treating a
  stationary touch as a click, so synthesized simulator taps work.

Verified on the iOS 27.2 Simulator (iPhone Duo, the only 27.2 runtime
in the local catalog; TVOut 1920×1080 via simctl io screenConfig):
official scene stayed up (legacy=0, extWin=Y, no loop), NTP and
Incognito painted on the external window, one-finger cursor move,
tap clicked Incognito and the omnibox, keyboard typed into the
omnibox, unplug restored Chrome to the phone, replug took over
again after a single bounce. Two-finger scroll was not visually
confirmed (no page with a scrollable document in that pass).

Apply after 0022. Device IPA: Views flag off, jitless default. Does
not include the uncommitted Views M1 (0021) work.
