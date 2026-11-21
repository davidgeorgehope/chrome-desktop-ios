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

// On-phone desktop: with no external display the desktop is laid out at a
// desktop width and drawn on the phone panel through a viewport,
//   panel point = origin + zoom * desktop point.
// The usable panel area is the scene minus the horizontal safe area.
struct Viewport {
  double zoom = 1;
  Point origin;
};

// Desktop widths for the phone panel. Landscape gets a laptop-class width;
// portrait (only allowed on squarer, larger devices) a narrower one that
// still gets desktop layouts.
inline constexpr double kPhoneDesktopLandscapeWidth = 1280;
inline constexpr double kPhoneDesktopPortraitWidth = 1024;
// How far past "fit" a pinch may zoom.
inline constexpr double kPhoneDesktopMaxZoomOverFit = 4;

// The desktop's size in DIPs: a desktop width, never narrower than the
// panel itself, and the panel's aspect ratio so "fit" fills it exactly.
constexpr Extent PhoneDesktopSize(Extent usable) {
  if (usable.width <= 0 || usable.height <= 0) {
    return {0, 0, kPhoneDesktopLandscapeWidth, 720};
  }
  const double base = usable.width >= usable.height
                          ? kPhoneDesktopLandscapeWidth
                          : kPhoneDesktopPortraitWidth;
  const double width = std::max(base, usable.width);
  // Whole DIPs; rounding down keeps "fit" from overflowing the panel.
  const double height =
      static_cast<double>(static_cast<long long>(width * usable.height /
                                                 usable.width));
  return {0, 0, width, height};
}

constexpr double FitZoom(Extent usable, Extent desktop) {
  if (desktop.width <= 0 || desktop.height <= 0) {
    return 1;
  }
  return std::min(usable.width / desktop.width,
                  usable.height / desktop.height);
}

// Zoom stays in [fit, fit * kPhoneDesktopMaxZoomOverFit] (at least 1:1). On
// each axis the desktop is centred when it is smaller than the panel and
// otherwise may not leave a gap at either edge.
constexpr Viewport ClampViewport(Viewport v, Extent usable, Extent desktop) {
  const double fit = FitZoom(usable, desktop);
  const double max_zoom = std::max(fit * kPhoneDesktopMaxZoomOverFit, 1.0);
  Viewport out;
  out.zoom = std::clamp(v.zoom, fit, max_zoom);
  auto axis = [](double origin, double panel_start, double panel_len,
                 double scaled_len) {
    if (scaled_len <= panel_len) {
      return panel_start + (panel_len - scaled_len) / 2;
    }
    return std::clamp(origin, panel_start + panel_len - scaled_len,
                      panel_start);
  };
  out.origin.x =
      axis(v.origin.x, usable.x, usable.width, desktop.width * out.zoom);
  out.origin.y =
      axis(v.origin.y, usable.y, usable.height, desktop.height * out.zoom);
  return out;
}

constexpr Viewport FitViewport(Extent usable, Extent desktop) {
  return ClampViewport({FitZoom(usable, desktop), {0, 0}}, usable, desktop);
}

constexpr Point PanelToDesktop(Viewport v, Point panel) {
  return {(panel.x - v.origin.x) / v.zoom, (panel.y - v.origin.y) / v.zoom};
}

constexpr Point DesktopToPanel(Viewport v, Point desktop) {
  return {v.origin.x + desktop.x * v.zoom, v.origin.y + desktop.y * v.zoom};
}

// Pinch: scales by |factor| keeping the desktop point under |anchor| (panel
// points) under it, moves by |pan| (panel points), then clamps.
constexpr Viewport PinchViewport(Viewport v,
                                 Point anchor,
                                 double factor,
                                 Point pan,
                                 Extent usable,
                                 Extent desktop) {
  const Point fixed = PanelToDesktop(v, anchor);
  Viewport out;
  out.zoom = v.zoom * factor;
  out.origin = {anchor.x - fixed.x * out.zoom + pan.x,
                anchor.y - fixed.y * out.zoom + pan.y};
  return ClampViewport(out, usable, desktop);
}

// Whether the phone panel may follow the device's rotation in on-phone
// desktop mode. Tall, narrow phones (iPhone 16 class, long side at least
// 1.8x the short side) are held in one landscape orientation; squarer,
// larger panels (iPhone Duo class) may rotate.
constexpr bool PanelMayRotate(double native_width, double native_height) {
  const double short_side = std::min(native_width, native_height);
  const double long_side = std::max(native_width, native_height);
  return short_side > 0 && long_side / short_side < 1.8;
}

}  // namespace views_trackpad_ios

#endif  // CHROME_BROWSER_UI_VIEWS_IOS_VIEWS_TRACKPAD_IOS_GEOMETRY_H_
