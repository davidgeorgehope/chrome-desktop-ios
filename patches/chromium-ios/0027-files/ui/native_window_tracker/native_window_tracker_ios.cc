// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ui/native_window_tracker/native_window_tracker_ios.h"

#include <memory>

namespace ui {

NativeWindowTrackerIOS::NativeWindowTrackerIOS(gfx::NativeWindow window)
    : window_(window) {}

NativeWindowTrackerIOS::~NativeWindowTrackerIOS() = default;

bool NativeWindowTrackerIOS::WasNativeWindowDestroyed() const {
  return !static_cast<bool>(window_);
}

// static
std::unique_ptr<NativeWindowTracker> NativeWindowTracker::Create(
    gfx::NativeWindow window) {
  return std::make_unique<NativeWindowTrackerIOS>(window);
}

}  // namespace ui
