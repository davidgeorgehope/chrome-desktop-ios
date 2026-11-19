// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/ui/tabs/tab_drag_api/desktop_tab_drag_impl/tab_drag_session_input_adapter_ios.h"

#include <utility>

#include "components/browser_apis/tab_drag/adapters/tab_drag_window_adapter.h"
#include "ui/display/screen.h"
#include "ui/events/event.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "ui/events/types/event_type.h"
#include "ui/views/event_monitor.h"

namespace tabs_api {

IOSInputAdapter::IOSInputAdapter() = default;

IOSInputAdapter::~IOSInputAdapter() {
  ReleaseInputCapture();
}

base::expected<void, mojo_base::mojom::ErrorPtr>
IOSInputAdapter::StartInputCapture(EventCallback callback,
                                   TabDragWindowAdapter* initial_window) {
  callback_ = std::move(callback);
  active_window_ = initial_window;
  suspended_ = false;
  StartMonitor();
  return base::ok();
}

void IOSInputAdapter::StartMonitor() {
  gfx::NativeWindow context =
      active_window_ ? active_window_->GetNativeWindow() : gfx::NativeWindow();
  monitor_ = views::EventMonitor::CreateApplicationMonitor(
      this, context,
      {ui::EventType::kMouseMoved, ui::EventType::kMouseDragged,
       ui::EventType::kMouseReleased, ui::EventType::kMouseCaptureChanged,
       ui::EventType::kKeyPressed});
}

void IOSInputAdapter::ReleaseInputCapture() {
  monitor_.reset();
  active_window_ = nullptr;
  callback_.Reset();
}

void IOSInputAdapter::SuspendInputCapture() {
  suspended_ = true;
  monitor_.reset();
}

void IOSInputAdapter::ResumeInputCapture() {
  suspended_ = false;
  if (!monitor_) {
    StartMonitor();
  }
}

void IOSInputAdapter::SetActiveWindowContext(TabDragWindowAdapter* new_window) {
  if (active_window_ == new_window) {
    return;
  }
  active_window_ = new_window;
  if (!suspended_) {
    StartMonitor();
  }
}

void IOSInputAdapter::OnEvent(const ui::Event& event) {
  if (!callback_ || suspended_) {
    return;
  }
  const gfx::Point screen_point =
      display::Screen::Get()->GetCursorScreenPoint();
  switch (event.type()) {
    case ui::EventType::kMouseMoved:
    case ui::EventType::kMouseDragged:
      callback_.Run({TabDragInputEvent::Type::kMoved, screen_point});
      break;
    case ui::EventType::kMouseReleased:
      callback_.Run({TabDragInputEvent::Type::kDropped, screen_point});
      break;
    case ui::EventType::kMouseCaptureChanged:
      callback_.Run({TabDragInputEvent::Type::kCaptureChanged});
      break;
    case ui::EventType::kKeyPressed:
      if (event.AsKeyEvent()->key_code() == ui::VKEY_ESCAPE) {
        callback_.Run({TabDragInputEvent::Type::kCancelled});
      }
      break;
    default:
      break;
  }
}

}  // namespace tabs_api
