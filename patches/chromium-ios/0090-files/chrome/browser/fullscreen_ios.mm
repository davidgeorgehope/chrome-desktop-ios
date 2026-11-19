// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/fullscreen.h"

// Mac asks whether another app owns a full-screen presentation so Chrome holds
// back notifications. An iOS app only ever sees its own scenes, and every
// scene fills its display, so there is no foreign full-screen app to defer to.
bool IsFullScreenMode() {
  return false;
}
