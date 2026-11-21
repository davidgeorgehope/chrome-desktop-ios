// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Compile-time checks of the cursor clamp, built into chrome_views_ios so a
// regression fails the build. Numbers are a 1920x1080 monitor at scale 1 and
// a 393x852 pt phone (scale 3), the setup the bounds once got confused with.

#include "chrome/browser/ui/views/ios/views_trackpad_ios_geometry.h"

namespace views_trackpad_ios {
namespace {

constexpr Extent kMonitor{0, 0, 1920, 1080};
constexpr Extent kPhone{0, 0, 393, 852};

constexpr bool Eq(Point a, Point b) {
  return a.x == b.x && a.y == b.y;
}

// Relative moves reach every edge of the monitor, not the phone's size.
static_assert(Eq(MoveCursor({960, 540}, {5000, 5000}, kMonitor), {1919, 1079}));
static_assert(Eq(MoveCursor({960, 540}, {-5000, -5000}, kMonitor), {0, 0}));
static_assert(Eq(MoveCursor({1500, 900}, {300, 100}, kMonitor), {1800, 1000}));
static_assert(Eq(MoveCursor({10, 10}, {1905, 1065}, kMonitor), {1915, 1075}));
// Far past the phone's 393x852 points (or 1179x2556 pixels) on both axes.
static_assert(MoveCursor({0, 0}, {1919, 1079}, kMonitor).x > 1179);
static_assert(MoveCursor({0, 0}, {1919, 1079}, kMonitor).y > 852);
// A display that is not at the origin keeps its own range.
static_assert(Eq(ClampToDisplay({0, 0}, {100, 50, 800, 600}), {100, 50}));
static_assert(Eq(ClampToDisplay({5000, 5000}, {100, 50, 800, 600}),
                 {899, 649}));
static_assert(Eq(ClampToDisplay({7, 7}, {0, 0, 0, 0}), {0, 0}));

// Phone-pointer fallback: phone-width travel spans the monitor width.
static_assert(PointerFallbackGain(kPhone, kMonitor, 2.5) * kPhone.width >=
              kMonitor.width);
static_assert(PointerFallbackGain(kPhone, kMonitor, 2.5) * kPhone.height >=
              kMonitor.height);
static_assert(PointerFallbackGain(kPhone, {0, 0, 800, 600}, 2.5) == 2.5);
static_assert(PointerFallbackGain({0, 0, 0, 0}, kMonitor, 2.5) == 2.5);

// The iOS pointer resting on a phone edge pins the cursor to that edge.
static_assert(Eq(PinToPhoneEdges({700, 400}, {393, 400}, kPhone, kMonitor),
                 {1919, 400}));
static_assert(Eq(PinToPhoneEdges({700, 400}, {0, 852}, kPhone, kMonitor),
                 {0, 1079}));
static_assert(Eq(PinToPhoneEdges({700, 400}, {200, 400}, kPhone, kMonitor),
                 {700, 400}));

// On-phone desktop (no monitor). iPhone 16 Pro in landscape: 874x402 pt with
// 62 pt safe areas left and right; iPhone Duo: 466x678 pt.
constexpr Extent k16ProUsable{62, 0, 750, 402};
constexpr Extent k16ProDesktop = PhoneDesktopSize(k16ProUsable);
constexpr bool Near(double a, double b) {
  return a - b < 1e-6 && b - a < 1e-6;
}
constexpr bool NearP(Point a, Point b) {
  return Near(a.x, b.x) && Near(a.y, b.y);
}
// A laptop-class desktop at the panel's aspect, so desktop sites lay out.
static_assert(k16ProDesktop.width == 1280 && k16ProDesktop.height == 686);
static_assert(PhoneDesktopSize({0, 0, 678, 466}).width == 1280);
static_assert(PhoneDesktopSize({0, 0, 466, 678}).width == 1024);
// A panel wider than the desktop width keeps its own width (1:1).
static_assert(PhoneDesktopSize({0, 0, 1366, 1024}).width == 1366);
// Fit fills the usable width and never overflows its height.
constexpr Viewport k16ProFit = FitViewport(k16ProUsable, k16ProDesktop);
static_assert(Near(k16ProFit.zoom, 750.0 / 1280));
static_assert(Near(k16ProFit.origin.x, 62));
static_assert(k16ProDesktop.height * k16ProFit.zoom <= 402);
// The desktop's corners land inside the usable panel.
static_assert(NearP(DesktopToPanel(k16ProFit, {0, 0}), k16ProFit.origin));
static_assert(DesktopToPanel(k16ProFit, {1280, 686}).x <= 62 + 750 + 1e-6);
// Round trip panel <-> desktop.
static_assert(NearP(PanelToDesktop(k16ProFit,
                                   DesktopToPanel(k16ProFit, {640, 300})),
                    {640, 300}));
// Pinching out past fit snaps back to fit; zoom is capped.
static_assert(Near(PinchViewport(k16ProFit, {400, 200}, 0.25, {0, 0},
                                 k16ProUsable, k16ProDesktop)
                       .zoom,
                   k16ProFit.zoom));
static_assert(PinchViewport(k16ProFit, {400, 200}, 100, {0, 0}, k16ProUsable,
                            k16ProDesktop)
                  .zoom <= k16ProFit.zoom * kPhoneDesktopMaxZoomOverFit);
// Zooming keeps the desktop point under the fingers in place.
constexpr Viewport kZoomed = PinchViewport(k16ProFit, {437, 201}, 2, {0, 0},
                                           k16ProUsable, k16ProDesktop);
static_assert(NearP(PanelToDesktop(kZoomed, {437, 201}),
                    PanelToDesktop(k16ProFit, {437, 201})));
// Panning a zoomed desktop stops at its edges (no gaps).
static_assert(Near(PinchViewport(kZoomed, {437, 201}, 1, {5000, 5000},
                                 k16ProUsable, k16ProDesktop)
                       .origin.x,
                   62));
static_assert(Near(PinchViewport(kZoomed, {437, 201}, 1, {-5000, 0},
                                 k16ProUsable, k16ProDesktop)
                           .origin.x +
                       1280 * kZoomed.zoom,
                   62 + 750));
// Orientation lock is by panel shape: iPhone 16 / 16 Pro / 16 Pro Max hold
// landscape, the squarer iPhone Duo may rotate.
static_assert(!PanelMayRotate(393, 852));
static_assert(!PanelMayRotate(402, 874));
static_assert(!PanelMayRotate(440, 956));
static_assert(PanelMayRotate(466, 678));
static_assert(PanelMayRotate(1024, 1366));

}  // namespace
}  // namespace views_trackpad_ios
