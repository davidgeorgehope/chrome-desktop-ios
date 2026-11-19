0135: build DisplayCALayerTree for iOS device, not only the Simulator.

The first arm64 device build of the desktop Views app
(out/Release-iphoneos-views, chrome_views_ios) failed to link:

    ld64.lld: error: undefined symbol: ui::DisplayCALayerTree::DisplayCALayerTree(CALayer*)
    >>> referenced by libviews.a(native_widget_ios.o) -[DeskBrowserViewsContentView initWithFrame:]

0017 limited display_ca_layer_tree.{h,mm} to target_environment ==
"simulator", but NativeWidgetIOS hosts its compositor output in a
DisplayCALayerTree on both. The iPhoneOS SDK's QuartzCore.tbd exports
CALayerHost, so the file links on device. The condition is now
`is_mac || is_ios`.

Apply after 0134 by copying 0135-files/ over Chromium src/.
