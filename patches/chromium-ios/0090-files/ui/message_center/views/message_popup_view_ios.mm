// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ui/message_center/views/message_popup_view.h"

#import <UIKit/UIKit.h>

#include "ui/views/widget/widget.h"

namespace message_center {

// NativeWidgetIOS::SetOpacity() sets the UIWindow alpha, so read it back from
// there (as Mac reads the NSWindow alphaValue).
float MessagePopupView::GetOpacity() const {
  if (!IsWidgetValid()) {
    return 0.f;
  }
  UIWindow* window = GetWidget()->GetNativeWindow().Get();
  return window ? window.alpha : 0.f;
}

}  // namespace message_center
