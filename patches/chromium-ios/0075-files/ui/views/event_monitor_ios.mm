// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ui/views/event_monitor.h"

#include <memory>

#include "base/memory/raw_ptr.h"
#include "ui/display/screen.h"
#include "ui/events/event_observer.h"

namespace views {

namespace {

// NativeWidgetIOS does not expose a global pre-target event hook yet, so this
// monitor only answers cursor-location queries.
// TODO(ios-desktop-views): Route NativeWidgetIOS events to observers.
class EventMonitorIOS : public EventMonitor {
 public:
  EventMonitorIOS(ui::EventObserver* event_observer, ui::EventTypeSet types)
      : event_observer_(event_observer), types_(types) {}
  EventMonitorIOS(const EventMonitorIOS&) = delete;
  EventMonitorIOS& operator=(const EventMonitorIOS&) = delete;
  ~EventMonitorIOS() override = default;

  gfx::Point GetLastMouseLocation() override {
    return display::Screen::Get()->GetCursorScreenPoint();
  }

 private:
  raw_ptr<ui::EventObserver> event_observer_;
  const ui::EventTypeSet types_;
};

}  // namespace

// static
std::unique_ptr<EventMonitor> EventMonitor::CreateApplicationMonitor(
    ui::EventObserver* event_observer,
    gfx::NativeWindow context,
    ui::EventTypeSet types) {
  return std::make_unique<EventMonitorIOS>(event_observer, types);
}

// static
std::unique_ptr<EventMonitor> EventMonitor::CreateWindowMonitor(
    ui::EventObserver* event_observer,
    gfx::NativeWindow target_window,
    ui::EventTypeSet types) {
  return std::make_unique<EventMonitorIOS>(event_observer, types);
}

}  // namespace views
