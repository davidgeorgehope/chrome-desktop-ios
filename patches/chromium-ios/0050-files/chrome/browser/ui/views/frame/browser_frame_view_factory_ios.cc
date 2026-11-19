// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <memory>

#include "chrome/browser/ui/views/frame/browser_view.h"
#include "chrome/browser/ui/views/frame/opaque_browser_frame_view.h"
#include "chrome/browser/ui/views/frame/opaque_browser_frame_view_layout.h"
#include "chrome/browser/ui/views/frame/picture_in_picture_browser_frame_view.h"

namespace chrome {

// iOS desktop Views (ENABLE_IOS_DESKTOP_VIEWS): there is no native window
// frame on the external display, so always use the opaque Views frame.
std::unique_ptr<BrowserFrameView> CreateBrowserFrameView(
    BrowserWidget* widget,
    BrowserView* browser_view) {
  if (browser_view->browser()->GetType() ==
      BrowserWindowInterface::Type::TYPE_FLOATING) {
    return std::make_unique<PictureInPictureBrowserFrameView>(widget,
                                                              browser_view);
  }
  auto opaque_browser_view = std::make_unique<OpaqueBrowserFrameView>(
      widget, browser_view, new OpaqueBrowserFrameViewLayout());
  opaque_browser_view->InitViews();
  return opaque_browser_view;
}

}  // namespace chrome
