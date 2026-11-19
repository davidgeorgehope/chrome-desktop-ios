// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "base/notimplemented.h"
#include "chrome/browser/ui/apps/chrome_app_window_client.h"

// Chrome Apps (platform app windows) are not supported by desktop Chrome on
// iOS. No app window can be created, so callers must not reach this.
extensions::NativeAppWindow* ChromeAppWindowClient::CreateNativeAppWindowImpl(
    extensions::AppWindow* app_window,
    const extensions::AppWindow::CreateParams& params) {
  NOTIMPLEMENTED();
  return nullptr;
}
