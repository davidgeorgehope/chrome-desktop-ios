iOS Views: desktop Chrome on the phone's own screen

Apply after 0141. Used by the desktop Views app (chrome_views_ios,
out/Release-iphoneos-views and the simulator).

What this patch does
--------------------
With no external display the app used to show "Connect a monitor". Now the
same desktop Chrome (tab strip, toolbar, omnibox, menus, desktop-mode sites)
runs on the phone's own screen, and moves live to a monitor when one is
plugged in and back when it is unplugged.

Design
- On-phone desktop. Widget UIWindows go on the phone's application scene.
  Each keeps its desktop size in points, so Views, the compositor and web
  content all lay out in desktop DIPs, and gets a scale transform that maps
  it onto the panel through one viewport: panel = origin + zoom * desktop.
  display::ScreenIos reports a single display at the desktop size while the
  on-phone desktop is active.
- Desktop size. Landscape uses a 1280-DIP-wide desktop and portrait 1024,
  never narrower than the panel, at the panel's aspect ratio (side safe
  areas excluded) so "fit" fills it. iPhone 16 Pro landscape: 1280x686 at
  zoom 0.586. iPhone Duo inner screen landscape: 1280x900 at 0.743.
- State. ui/display/ios/phone_desktop_ios.h holds the viewport. The phone
  input view (ChromeViewsIOSTrackpadView) owns it, and NativeWidgetIOS and
  ScreenIos read it. The input view switches mode on scene connect and
  disconnect, so widgets and input change mode together.
- Input. On the phone the input view is a transparent window above the
  desktop (it stays key, so hardware keys and the on-screen keyboard keep
  working). A tap clicks where it lands. A long press or two-finger tap
  right-clicks. One finger scrolls what is under it, with a fling. Pinch
  and two-finger drag zoom (fit to 4x fit) and pan the desktop. A hardware
  mouse (GCMouse, or the iOS pointer mapped 1:1) and keyboard work as on the
  monitor; the cursor is drawn only once a mouse has moved it.
- On-screen keyboard. It comes up after a click that focuses a text field
  (web input or a Views textfield such as the omnibox) and goes away after a
  click elsewhere or Return.
- Orientation, by device class (panel shape, not model). Tall phones (long
  side at least 1.8x the short side: iPhone 16 / 16 Pro / Pro Max) are held
  in landscape-right while the desktop is on the phone. Squarer panels
  (iPhone Duo) follow the device. With a monitor the app keeps its usual
  orientations and the phone is the trackpad, as before.
- Holding the lock. iOS asks the root controller of the topmost full-screen
  window about orientation and the status bar. That can be the input window,
  any widget window, or the cursor window, so all three answer the same: on a
  tall phone they allow only landscape-right and hide the status bar while
  the desktop is on the phone. Before this, the cursor window's plain
  controller allowed portrait, so turning the phone re-laid the scene out in
  portrait (the desktop ended up in a corner under the status bar). Now
  turning the phone leaves the desktop full size and sideways. If iOS still
  shows portrait (for a moment at launch), the desktop keeps its landscape
  layout and an opaque "turn to landscape" screen covers it until iOS
  applies the lock; input is ignored meanwhile.
- Status bar. Hidden by every root controller while the desktop is on the
  phone. The layout also keeps out of the top safe-area inset, so status
  never covers Chromium.
- Restore bubble. iOS ends apps by killing them (swipe away, memory
  pressure, updates), so Chrome never records a clean exit and offered
  "Restore pages? Chromium didn't shut down correctly" on every launch. The
  app now adds --hide-crash-restore-bubble to its own command line unless
  it is already there.
- Which screen is the monitor. ScreenIos used to treat every screen other
  than UIScreen.mainScreen as the monitor. On the iPhone Duo the unfolded
  inner panel is a screen of its own, so with a monitor attached the panel
  (951x669) became the primary display, and web content on the monitor was
  drawn in a 951x669 corner over the compositor's red background. The
  primary display is now the screen of the external-display scene; screens
  of application-role scenes count as the phone.
- Display changes reach web views. Entering or leaving the on-phone desktop
  (or resizing it) refreshes the display list, and every display-list
  refresh posts DeskBrowserDisplaysChangedForIOS so the render widget host
  view refreshes its screen info even when its own size has not changed.
- Surface ids. BrowserCompositorIOS now allocates a new renderer surface id
  when the screen size changes. The renderer's compositor viewport is the
  screen rect, so a display resize with an unchanged view size (seen when
  the Duo unfolds) sent a new size with the old id and tripped a DCHECK in
  AsyncLayerTreeFrameSink.
- Compile-time checks in views_trackpad_ios_geometry_checks.cc cover the
  desktop size, fit, pinch anchoring, pan clamping and the orientation rule.

Simulator check (iPhone 16 Pro, iOS 26.5; iPhone Duo, iOS 27.2)
- iPhone 16 Pro: launches locked to landscape-right, with a 1280x686 desktop.
  github.com and youtube.com load in desktop layout. Taps open web menus,
  a long press opens the context menu, and pinch zooms. Tapping the omnibox
  brings up the keyboard, and typing plus Return navigates.
- iPhone 16 Pro rotation (device orientation sent with
  tools/ios-views-onphone/simrotate.m): device portrait, landscape-left and
  portrait again leave the interface in landscape-right with the desktop
  full size; the status bar stays hidden.
- Monitor mode on the iPhone Duo (inner screen) and iPhone 16 Pro: after
  plugging in a 1920x1080 TVOut the page fills the monitor with no red area.
- Restore bubble: launched without the flag, killed with SIGKILL, and
  relaunched; no "Restore pages?" bubble.
- iPhone Duo: outer screen in portrait and landscape, inner screen in
  portrait and landscape. Plugging in a 1920x1080 TVOut moves the desktop to
  the monitor and turns the phone into the trackpad. Unplugging brings it
  back to the phone, with no crash.

Known gaps
- No text selection by touch drag (one finger scrolls); use a
  mouse, or a long press for the context menu.
- The on-screen keyboard covers the bottom of the panel; at fit zoom the
  desktop cannot scroll up above it (zoom in and pan, or use the omnibox).
- StackAtTop on the phone does not reorder already-visible windows.

Replace the listed files with the copies in this directory.
