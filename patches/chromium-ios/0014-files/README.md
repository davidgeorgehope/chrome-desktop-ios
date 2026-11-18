Follow-up GN gates after 0013 so `gn gen` succeeds for
`enable_ios_desktop_views=true` in out/Release-iphonesimulator-views.

- ui/views test_support: do not depend on //ui/native_window_tracker
  on iOS (that component asserts use_aura || is_mac || is_android).
- ui/resources test pak: when toolkit_views is true, add
  //third_party/blink/public:resources_grit as a dep so the
  blink_resources.pak listed in the views repack is generated on iOS.

`gn gen` of that out produced 37206 targets (18 Nov 2026, 3:00 PM ET).
Apply after 0013.
