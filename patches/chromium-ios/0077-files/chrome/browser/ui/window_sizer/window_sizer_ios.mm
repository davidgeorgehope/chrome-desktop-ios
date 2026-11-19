// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/ui/window_sizer/window_sizer.h"

#include <algorithm>

#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "ui/display/display.h"
#include "ui/display/screen.h"
#include "ui/gfx/geometry/rect.h"

// Same tiling as Mac: desktop Chrome on iOS runs on an external display with
// Views windows positioned in DIPs, top-left origin.
const int WindowSizer::kWindowTilePixels = 22;
const int WindowSizer::kWindowMaxDefaultWidth = 1200;

// static
gfx::Point WindowSizer::GetDefaultPopupOrigin(const gfx::Size& size) {
  display::Screen* screen = display::Screen::Get();
  gfx::Rect work_area = screen->GetPrimaryDisplay().work_area();
  gfx::Point corner = work_area.origin();

  if (BrowserWindowInterface* browser =
          GlobalBrowserCollection::GetInstance()->GetLastActiveBrowser()) {
    gfx::Rect window_bounds = browser->GetWindow()->GetBounds();
    work_area = screen->GetDisplayMatching(window_bounds).work_area();
    // Offset from the active window, without overflowing the right and bottom
    // edges, then keep the title area on screen at the left and top.
    gfx::Point limit(
        std::min(window_bounds.x() + kWindowTilePixels,
                 work_area.right() - size.width()),
        std::min(window_bounds.y() + kWindowTilePixels,
                 work_area.bottom() - size.height()));
    corner = gfx::Point(std::max(work_area.x(), limit.x()),
                        std::max(work_area.y(), limit.y()));
  }
  return corner;
}
