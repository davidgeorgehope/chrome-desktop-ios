// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CHROME_BROWSER_UI_VIEWS_FRAME_BROWSER_NATIVE_WIDGET_IOS_H_
#define CHROME_BROWSER_UI_VIEWS_FRAME_BROWSER_NATIVE_WIDGET_IOS_H_

#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/views/frame/browser_native_widget.h"
#include "ui/views/widget/native_widget_ios.h"

class BrowserView;
class BrowserWidget;

// BrowserNativeWidget for iOS desktop Views (ENABLE_IOS_DESKTOP_VIEWS).
// Hosts the browser Widget in a UIWindow via views::NativeWidgetIOS, which
// prefers the external display (TVOut) scene when one is connected.
class BrowserNativeWidgetIOS : public views::NativeWidgetIOS,
                               public BrowserNativeWidget {
 public:
  BrowserNativeWidgetIOS(BrowserWidget* browser_widget,
                         BrowserView* browser_view);
  BrowserNativeWidgetIOS(const BrowserNativeWidgetIOS&) = delete;
  BrowserNativeWidgetIOS& operator=(const BrowserNativeWidgetIOS&) = delete;
  ~BrowserNativeWidgetIOS() override;

  // BrowserNativeWidget:
  views::Widget::InitParams GetWidgetParams(
      views::Widget::InitParams::Ownership ownership) override;
  bool UseCustomFrame() const override;
  bool UsesNativeSystemMenu() const override;
  bool ShouldSaveWindowPlacement() const override;
  void GetWindowPlacement(
      gfx::Rect* bounds,
      ui::mojom::WindowShowState* show_state) const override;
  content::KeyboardEventProcessingResult PreHandleKeyboardEvent(
      const input::NativeWebKeyboardEvent& event) override;
  bool HandleKeyboardEvent(const input::NativeWebKeyboardEvent& event) override;
  bool ShouldRestorePreviousBrowserWidgetState() const override;
  bool ShouldUseInitialVisibleOnAllWorkspaces() const override;

 private:
  raw_ptr<BrowserView> browser_view_;
};

#endif  // CHROME_BROWSER_UI_VIEWS_FRAME_BROWSER_NATIVE_WIDGET_IOS_H_
