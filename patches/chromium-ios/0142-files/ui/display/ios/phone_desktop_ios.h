// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef UI_DISPLAY_IOS_PHONE_DESKTOP_IOS_H_
#define UI_DISPLAY_IOS_PHONE_DESKTOP_IOS_H_

#include "ui/display/display_export.h"
#include "ui/gfx/geometry/point_f.h"
#include "ui/gfx/geometry/size.h"

namespace display {

// On-phone desktop (desktop Views on iOS with no external display): the
// desktop is laid out at |size| DIPs and drawn on the phone panel at |zoom|
// panel points per DIP, with desktop (0, 0) at panel point |origin|. Set by
// the phone input host on the UI thread. While |active| the panel is the one
// display and its bounds are |size|.
struct PhoneDesktopForIOS {
  bool active = false;
  gfx::Size size;
  gfx::PointF origin;
  float zoom = 1.0f;
  // Tall phones (iPhone 16 class) hold the on-phone desktop in
  // landscape-right; every window's controller must agree, or iOS rotates
  // the scene with the device.
  bool landscape_right_only = false;
};

DISPLAY_EXPORT void SetPhoneDesktopForIOS(const PhoneDesktopForIOS& desktop);
DISPLAY_EXPORT const PhoneDesktopForIOS& GetPhoneDesktopForIOS();

// UIWindow tag of the phone's input overlay. It sits above the desktop's
// windows to take touches, so window-at-point lookups skip it.
inline constexpr long kPhoneInputOverlayWindowTagForIOS = 0x44425050;

}  // namespace display

#endif  // UI_DISPLAY_IOS_PHONE_DESKTOP_IOS_H_
