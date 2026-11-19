// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef UI_VIEWS_EXAMPLES_IOS_DESKTOP_BROWSER_CHROME_VIEW_H_
#define UI_VIEWS_EXAMPLES_IOS_DESKTOP_BROWSER_CHROME_VIEW_H_

#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/gfx/geometry/point.h"
#include "ui/views/view.h"

namespace views {
class Textfield;
}

// M2 host chrome: a desktop-style tab strip + toolbar + contents pane,
// laid out like Chromium's BrowserView (non-touch layout_constants).
// This is the Views stepping stone toward hosting the real
// chrome/browser/ui/views BrowserView once that GN graph compiles on iOS.
class DesktopBrowserChromeView : public views::View {
  METADATA_HEADER(DesktopBrowserChromeView, views::View)

 public:
  DesktopBrowserChromeView();
  DesktopBrowserChromeView(const DesktopBrowserChromeView&) = delete;
  DesktopBrowserChromeView& operator=(const DesktopBrowserChromeView&) = delete;
  ~DesktopBrowserChromeView() override;

  // Move a software cursor (phone trackpad) in widget DIP coordinates
  // relative to this view. |click| synthesizes a left press+release.
  void OnTrackpadMove(const gfx::Point& point_in_view, bool click);

  views::View* cursor_view() { return cursor_view_; }

  // views::View:
  void AddedToWidget() override;
  void Layout(PassKey) override;

 private:
  void OnTabSelected(int index);

  class TabStripBar;
  class ToolbarBar;
  class ContentsPane;
  class CursorOverlay;

  raw_ptr<TabStripBar> tab_strip_ = nullptr;
  raw_ptr<ToolbarBar> toolbar_ = nullptr;
  raw_ptr<ContentsPane> contents_ = nullptr;
  raw_ptr<views::View> cursor_view_ = nullptr;
};

#endif  // UI_VIEWS_EXAMPLES_IOS_DESKTOP_BROWSER_CHROME_VIEW_H_
