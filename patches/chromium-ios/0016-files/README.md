NativeWidgetIOS, ViewsDelegate context factory, and Milestone 1
Simulator host for desktop Views on iOS.

After 0015, `autoninja ui/views` in out/Release-iphonesimulator-views
nearly compiled, then failed on iOS-missing paths that assumed
"not Mac ⇒ Aura". This patch:

- Adds `ui/views/widget/native_widget_ios.h` / `.mm`: a UIKit
  NativeWidget that hosts an on-screen compositor via
  CALayerFrameSinkProvider + DisplayCALayerTree (Simulator only).
  Mac/Win-only NativeWidget methods are omitted; IME uses
  ui/base/ime/init/input_method_factory.h.
- Opens ViewsDelegate::GetContextFactory() to iOS.
- Adds a generic ViewAccessibility::Create fallback under
  HAS_NATIVE_ACCESSIBILITY so iOS compiles (-Wreturn-type).
- Treats iOS like Mac (non-Aura) in bubble_dialog_delegate_view.cc
  so ui/aura/window.h is not included.
- Wires the iOS sources in ui/views/BUILD.gn with `frameworks =`
  (the `frameworks` list is not defined outside the is_mac block).
- Adds `//ui/views/examples/ios:views_examples_ios` (group
  `views_examples_ios`) — a testonly Simulator host that creates
  one Views widget. Build with the short ninja target name
  `views_examples_ios` (siso collapses a `//` GN label to `/`).

`autoninja ui/views` succeeded at 3:30:01 PM ET on 18 Nov 2026.
The host app may still need further compile/runtime iteration.

Apply `../0016-ios-desktop-views-native-widget-ios.patch` after 0015.
