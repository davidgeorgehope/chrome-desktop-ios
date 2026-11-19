// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/media/webrtc/window_icon_util.h"

#include "ui/gfx/image/image_skia.h"

// iOS exposes no other apps' windows to capture, so there is no window icon.
gfx::ImageSkia GetWindowIcon(content::DesktopMediaID id) {
  return gfx::ImageSkia();
}
