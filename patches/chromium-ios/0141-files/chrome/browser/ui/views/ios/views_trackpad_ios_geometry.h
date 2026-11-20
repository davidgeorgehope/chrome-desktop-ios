// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CHROME_BROWSER_UI_VIEWS_IOS_VIEWS_TRACKPAD_IOS_GEOMETRY_H_
#define CHROME_BROWSER_UI_VIEWS_IOS_VIEWS_TRACKPAD_IOS_GEOMETRY_H_

#include <algorithm>

// Cursor geometry for the phone trackpad and hardware mouse. All cursor
// positions are in desktop DIPs: the external display's UIKit points, which
// display::ScreenIos reports as the primary display's bounds. Kept free of
// UIKit so the math can be checked at compile time.
namespace views_trackpad_ios {

struct Extent {
  double x = 0;
  double y = 0;
  double width = 0;
  double height = 0;
};

struct Point {
  double x = 0;
  double y = 0;
};

// Keeps |p| on a pixel of |display|: [x, x + width - 1] by
// [y, y + height - 1]. An empty display pins the cursor to its origin.
constexpr Point ClampToDisplay(Point p, Extent display) {
  const double max_x = display.x + std::max(display.width - 1, 0.0);
  const double max_y = display.y + std::max(display.height - 1, 0.0);
  return {std::clamp(p.x, display.x, max_x), std::clamp(p.y, display.y, max_y)};
}

// Moves the cursor by a relative delta, then clamps it to the display.
constexpr Point MoveCursor(Point cursor, Point delta, Extent display) {
  return ClampToDisplay({cursor.x + delta.x, cursor.y + delta.y}, display);
}

// Gain for the phone-pointer fallback. The iOS pointer stops at the phone's
// edges, so phone-sized travel must be able to cover the whole display on
// both axes; never slower than the finger trackpad gain.
constexpr double PointerFallbackGain(Extent phone,
                                     Extent display,
                                     double min_gain) {
  if (phone.width <= 0 || phone.height <= 0) {
    return min_gain;
  }
  return std::max({min_gain, display.width / phone.width,
                   display.height / phone.height});
}

// When the iOS pointer sits on an edge of the phone view it can go no
// further and reports no more motion, so the cursor is pinned to the same
// edge of the display. Elsewhere the cursor moves by relative deltas only.
// Returns |cursor| with the pinned axes replaced.
constexpr Point PinToPhoneEdges(Point cursor,
                                Point phone_pointer,
                                Extent phone,
                                Extent display) {
  constexpr double kEdge = 1.0;
  Point out = cursor;
  if (phone_pointer.x <= phone.x + kEdge) {
    out.x = display.x;
  } else if (phone_pointer.x >= phone.x + phone.width - kEdge) {
    out.x = display.x + display.width - 1;
  }
  if (phone_pointer.y <= phone.y + kEdge) {
    out.y = display.y;
  } else if (phone_pointer.y >= phone.y + phone.height - kEdge) {
    out.y = display.y + display.height - 1;
  }
  return ClampToDisplay(out, display);
}

}  // namespace views_trackpad_ios

#endif  // CHROME_BROWSER_UI_VIEWS_IOS_VIEWS_TRACKPAD_IOS_GEOMETRY_H_
