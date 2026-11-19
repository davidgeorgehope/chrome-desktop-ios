// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/lifetime/application_lifetime_desktop.h"

#include "base/check.h"
#include "ui/views/widget/widget.h"

namespace chrome {

// All browsers are closed. iOS apps do not terminate themselves, so the only
// platform work is closing any NativeWidgetIOS that UIKit still holds so their
// compositors go away before the GPU host does.
void HandleAppExitingForPlatform() {
  static bool exiting = false;
  CHECK(!exiting);
  exiting = true;
  views::Widget::CloseAllWidgets();
}

}  // namespace chrome
