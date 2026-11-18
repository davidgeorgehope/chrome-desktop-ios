Post-0016 Simulator Views host and compositor compile/runtime fixes.

0016 added NativeWidgetIOS and a first views_examples_ios host, and
`autoninja ui/views` succeeded, but the host did not yet link or stay
up on the Simulator. This patch:

- Enables DisplayCALayerTree when `target_environment == "simulator"`.
  The previous condition used `target_platform != "iphoneos"`, which is
  never true: both device and Simulator set `target_platform` to
  "iphoneos".
- Registers the CALayerFrameSinkProvider handle in `-initWithFrame:`
  (the UIView designated initializer). Views content views were going
  through that path, so the handle stayed 0 and compositor lookup
  failed.
- Routes iOS + toolkit_views drag-and-drop through
  OSExchangeDataProviderNonBacked, and gates Html methods (Aura-only)
  with `USE_AURA`. InputMethod factory uses IS_MAC so iOS gets
  InputMethodMinimal.
- Makes ScreenIos collect UIWindowScene.screen and fall back to
  UIScreen.mainScreen when no window-backed displays exist yet, so
  display_finder is not empty during scene connect.
- Adds iOS stubs for MenuConfig, MenuPreTargetHandler, and metrics.
- Prefers the UIWindowSceneSessionRoleApplication scene in
  NativeWidgetIOS::FirstWindowScene so a widget is not placed on
  AirPlay/TVOut by accident.
- Updates the views_examples_ios host so it actually launches: separate
  WidgetDelegate + View (WidgetDelegateView's default ctor is private),
  LayoutProvider, ScopedNativeScreen, AXPlatformForTest, ThreadPool,
  color mixers, ui_test.pak in the bundle, and CFBundleName
  `views_examples_ios` so codesign succeeds. The M1 widget is a red
  frameless 370x260 view at (16, 96).

The host launches and places the widget window, but compositor frames
are not yet presenting (the placed view stays the UIKit background,
not the red Views Label). That is the next Views Milestone 1 step.

Apply `../0017-ios-desktop-views-host-and-compositor-fixes.patch` after
0016.
