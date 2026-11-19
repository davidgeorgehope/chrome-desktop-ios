// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CHROME_BROWSER_UI_TABS_TAB_DRAG_API_DESKTOP_TAB_DRAG_IMPL_TAB_DRAG_SESSION_INPUT_ADAPTER_IOS_H_
#define CHROME_BROWSER_UI_TABS_TAB_DRAG_API_DESKTOP_TAB_DRAG_IMPL_TAB_DRAG_SESSION_INPUT_ADAPTER_IOS_H_

#include <memory>

#include "base/memory/raw_ptr.h"
#include "base/types/expected.h"
#include "components/browser_apis/tab_drag/adapters/tab_drag_session_input_adapter.h"
#include "mojo/public/mojom/base/error.mojom.h"
#include "ui/events/event_observer.h"

namespace views {
class EventMonitor;
}

namespace tabs_api {

class TabDragWindowAdapter;

// Watches Views input on the NativeWidgetIOS windows through an application
// event monitor; UIKit has no global pointer capture to take.
class IOSInputAdapter : public TabDragSessionInputAdapter,
                        public ui::EventObserver {
 public:
  IOSInputAdapter();
  ~IOSInputAdapter() override;

  // TabDragSessionInputAdapter:
  base::expected<void, mojo_base::mojom::ErrorPtr> StartInputCapture(
      EventCallback callback,
      TabDragWindowAdapter* initial_window) override;
  void ReleaseInputCapture() override;
  void SuspendInputCapture() override;
  void ResumeInputCapture() override;
  void SetActiveWindowContext(TabDragWindowAdapter* new_window) override;

  // ui::EventObserver:
  void OnEvent(const ui::Event& event) override;

 private:
  void StartMonitor();

  EventCallback callback_;
  raw_ptr<TabDragWindowAdapter> active_window_ = nullptr;
  std::unique_ptr<views::EventMonitor> monitor_;
  bool suspended_ = false;
};

}  // namespace tabs_api

#endif  // CHROME_BROWSER_UI_TABS_TAB_DRAG_API_DESKTOP_TAB_DRAG_IMPL_TAB_DRAG_SESSION_INPUT_ADAPTER_IOS_H_
