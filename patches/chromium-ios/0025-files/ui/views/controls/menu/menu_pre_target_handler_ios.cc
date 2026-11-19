// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ui/views/controls/menu/menu_pre_target_handler.h"

namespace views {

namespace {

class MenuPreTargetHandlerIOS : public MenuPreTargetHandler {
 public:
  MenuPreTargetHandlerIOS(MenuController*, Widget*) {}
};

}  // namespace

std::unique_ptr<MenuPreTargetHandler> MenuPreTargetHandler::Create(
    MenuController* controller,
    Widget* widget) {
  return std::make_unique<MenuPreTargetHandlerIOS>(controller, widget);
}

}  // namespace views
