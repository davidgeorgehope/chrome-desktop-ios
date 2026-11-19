// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "components/input/native_web_keyboard_event.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "ui/events/event.h"
#include "ui/events/event_constants.h"
#include "ui/events/keycodes/dom/dom_code.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "ui/views/controls/webview/unhandled_keyboard_event_handler.h"
#include "ui/views/focus/focus_manager.h"

namespace views {

// static
bool UnhandledKeyboardEventHandler::HandleNativeKeyboardEvent(
    const input::NativeWebKeyboardEvent& event,
    FocusManager* focus_manager) {
  if (event.skip_if_unhandled || !focus_manager) {
    return false;
  }

  // The iOS NativeEvent is a UIKit event, not a ui::Event, so rebuild the
  // ui::KeyEvent from the Blink event and give Views accelerators a chance.
  ui::EventType type;
  switch (event.GetType()) {
    case blink::WebInputEvent::Type::kRawKeyDown:
    case blink::WebInputEvent::Type::kKeyDown:
      type = ui::EventType::kKeyPressed;
      break;
    case blink::WebInputEvent::Type::kKeyUp:
      type = ui::EventType::kKeyReleased;
      break;
    default:
      return false;
  }

  const int modifiers = event.GetModifiers();
  int flags = ui::EF_NONE;
  if (modifiers & blink::WebInputEvent::kShiftKey) {
    flags |= ui::EF_SHIFT_DOWN;
  }
  if (modifiers & blink::WebInputEvent::kControlKey) {
    flags |= ui::EF_CONTROL_DOWN;
  }
  if (modifiers & blink::WebInputEvent::kAltKey) {
    flags |= ui::EF_ALT_DOWN;
  }
  if (modifiers & blink::WebInputEvent::kMetaKey) {
    flags |= ui::EF_COMMAND_DOWN;
  }

  ui::KeyEvent key_event(type,
                         static_cast<ui::KeyboardCode>(event.windows_key_code),
                         static_cast<ui::DomCode>(event.dom_code), flags);
  return !focus_manager->OnKeyEvent(key_event);
}

}  // namespace views
