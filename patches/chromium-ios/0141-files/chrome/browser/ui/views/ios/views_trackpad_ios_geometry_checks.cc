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

}  // namespace
}  // namespace views_trackpad_ios
