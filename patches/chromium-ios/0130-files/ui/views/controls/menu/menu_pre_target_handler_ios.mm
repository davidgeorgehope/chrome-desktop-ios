// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ui/views/controls/menu/menu_pre_target_handler.h"

#include "base/memory/raw_ptr.h"
#include "ui/events/event.h"
#include "ui/views/controls/menu/menu_controller.h"
#include "ui/views/widget/native_widget_ios.h"

namespace views {

namespace {

// Lets the MenuController see trackpad key events (Escape, arrows, Return)
// before the focused widget, as MenuPreTargetHandlerMac does on macOS.
class MenuPreTargetHandlerIOS : public MenuPreTargetHandler,
                                public NativeWidgetIOS::KeyEventMonitor {
 public:
  explicit MenuPreTargetHandlerIOS(MenuController* controller)
      : controller_(controller) {
    NativeWidgetIOS::AddKeyEventMonitor(this);
  }
  MenuPreTargetHandlerIOS(const MenuPreTargetHandlerIOS&) = delete;
  MenuPreTargetHandlerIOS& operator=(const MenuPreTargetHandlerIOS&) = delete;
  ~MenuPreTargetHandlerIOS() override {
    NativeWidgetIOS::RemoveKeyEventMonitor(this);
  }

  // NativeWidgetIOS::KeyEventMonitor:
  bool OnTrackpadKeyEvent(ui::KeyEvent* event) override {
    if (controller_->HasFocusedTextfield()) {
      return false;
    }
    return controller_->OnWillDispatchKeyEvent(event) !=
           ui::POST_DISPATCH_PERFORM_DEFAULT;
  }

 private:
  const raw_ptr<MenuController> controller_;  // Owns |this|.
};

}  // namespace

// static
std::unique_ptr<MenuPreTargetHandler> MenuPreTargetHandler::Create(
    MenuController* controller,
    Widget* widget) {
  return std::make_unique<MenuPreTargetHandlerIOS>(controller);
}

}  // namespace views
