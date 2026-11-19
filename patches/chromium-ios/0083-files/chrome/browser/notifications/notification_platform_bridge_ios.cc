// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/notifications/notification_platform_bridge.h"

// iOS Views shows web notifications through the message center; there is no
// system bridge yet (see the iOS cut list in docs/desktop-chrome-ios-plan.md).
// static
bool NotificationPlatformBridge::CanHandleType(
    NotificationHandler::Type notification_type) {
  return false;
}
