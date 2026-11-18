GN enablement for desktop Views on iOS (Milestone 1 of
docs/desktop-chrome-ios-plan.md).

Adds `enable_ios_desktop_views` (default false) so
`toolkit_views` can be true on iOS without changing the existing
//ios/chrome outs. Widens the grit toolkit_views assert, and
keeps root views_examples / views_unittests / watermark_app out
of the iOS default graph.

A dedicated out dir should set:

  enable_ios_desktop_views = true
  use_aura = false
  enable_library_cdms = false

Also gates `//components/constrained_window` unit/browser tests
out of the iOS components test graph (those tests pulled
`web_modal`, which asserts `!is_ios`, as soon as toolkit_views
was true). Further desktop-only asserts may still appear during
`gn gen`. Apply this patch, then continue gating or stubbing
until `autoninja ui/views` succeeds.

Apply `../0013-enable-ios-desktop-views-gn.patch` after 0012.
