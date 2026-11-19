// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/download/drag_download_item.h"

#include "base/notimplemented.h"

// iOS desktop Views: dragging a download out of the browser is not wired yet.
void DragDownloadItem(const download::DownloadItem* download,
                      const gfx::Image* icon,
                      gfx::NativeView view) {
  NOTIMPLEMENTED_LOG_ONCE();
}
