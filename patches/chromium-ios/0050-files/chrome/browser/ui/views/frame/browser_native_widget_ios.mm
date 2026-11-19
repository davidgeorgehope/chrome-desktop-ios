// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/ui/views/frame/browser_native_widget_ios.h"

#include "chrome/browser/ui/views/frame/browser_view.h"
#include "chrome/browser/ui/views/frame/browser_widget.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "ui/base/mojom/window_show_state.mojom.h"

BrowserNativeWidgetIOS::BrowserNativeWidgetIOS(BrowserWidget* browser_widget,
                                               BrowserView* browser_view)
    : views::NativeWidgetIOS(browser_widget), browser_view_(browser_view) {}

BrowserNativeWidgetIOS::~BrowserNativeWidgetIOS() = default;

views::Widget::InitParams BrowserNativeWidgetIOS::GetWidgetParams(
    views::Widget::InitParams::Ownership ownership) {
  views::Widget::InitParams params(ownership);
  params.native_widget = this;
  return params;
}

bool BrowserNativeWidgetIOS::UseCustomFrame() const {
  return true;
}

bool BrowserNativeWidgetIOS::UsesNativeSystemMenu() const {
  return false;
}

bool BrowserNativeWidgetIOS::ShouldSaveWindowPlacement() const {
  return false;
}

void BrowserNativeWidgetIOS::GetWindowPlacement(
    gfx::Rect* bounds,
    ui::mojom::WindowShowState* show_state) const {
  *bounds = GetRestoredBounds();
  *show_state = ui::mojom::WindowShowState::kMaximized;
}

content::KeyboardEventProcessingResult
BrowserNativeWidgetIOS::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  return content::KeyboardEventProcessingResult::NOT_HANDLED;
}

bool BrowserNativeWidgetIOS::HandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  return false;
}

bool BrowserNativeWidgetIOS::ShouldRestorePreviousBrowserWidgetState() const {
  return false;
}

bool BrowserNativeWidgetIOS::ShouldUseInitialVisibleOnAllWorkspaces() const {
  return true;
}
