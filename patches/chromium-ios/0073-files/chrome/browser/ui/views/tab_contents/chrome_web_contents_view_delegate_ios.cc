// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <memory>

#include "chrome/browser/ui/tab_contents/chrome_web_contents_view_delegate.h"
#include "content/public/browser/web_contents_view_delegate.h"

// iOS desktop Views: the Aura delegate needs RenderViewContextMenuViews (Aura
// only) and the Mac one needs Cocoa. WebContentsViewIOS treats a null delegate
// as "no context menu / focus hooks".
std::unique_ptr<content::WebContentsViewDelegate> CreateWebContentsViewDelegate(
    content::WebContents* web_contents) {
  return nullptr;
}
