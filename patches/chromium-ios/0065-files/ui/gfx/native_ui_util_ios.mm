// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ui/gfx/native_ui_util.h"

#import <UIKit/UIKit.h>

#include "base/check.h"

namespace gfx {

gfx::NativeView GetViewForWindow(gfx::NativeWindow native_window) {
  UIWindow* window = native_window.Get();
  DCHECK(window);
  UIView* content_view = window.rootViewController.view;
  return gfx::NativeView(content_view ? content_view : window);
}

}  // namespace gfx
