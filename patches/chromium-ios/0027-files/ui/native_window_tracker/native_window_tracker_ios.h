// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef UI_NATIVE_WINDOW_TRACKER_NATIVE_WINDOW_TRACKER_IOS_H_
#define UI_NATIVE_WINDOW_TRACKER_NATIVE_WINDOW_TRACKER_IOS_H_

#include "base/component_export.h"
#include "ui/gfx/native_ui_types.h"
#include "ui/native_window_tracker/native_window_tracker.h"

namespace ui {

// Tracks a UIWindow via gfx::NativeWindow (a WeakUIWindow). The window is
// considered destroyed once that weak reference clears.
class COMPONENT_EXPORT(UI_NATIVE_WINDOW_TRACKER) NativeWindowTrackerIOS
    : public NativeWindowTracker {
 public:
  explicit NativeWindowTrackerIOS(gfx::NativeWindow window);

  NativeWindowTrackerIOS(const NativeWindowTrackerIOS&) = delete;
  NativeWindowTrackerIOS& operator=(const NativeWindowTrackerIOS&) = delete;

  ~NativeWindowTrackerIOS() override;

  // NativeWindowTracker:
  bool WasNativeWindowDestroyed() const override;

 private:
  gfx::NativeWindow window_;
};

}  // namespace ui

#endif  // UI_NATIVE_WINDOW_TRACKER_NATIVE_WINDOW_TRACKER_IOS_H_
