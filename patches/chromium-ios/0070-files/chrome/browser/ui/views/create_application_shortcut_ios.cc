// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <string>

#include "base/functional/callback.h"
#include "base/notimplemented.h"
#include "chrome/browser/ui/dialogs/browser_dialogs.h"

// iOS desktop Views cannot place app shortcuts on the home screen, so the
// dialogs report that nothing was created.

namespace chrome {

void ShowCreateChromeAppShortcutsDialog(
    gfx::NativeWindow parent_window,
    Profile* profile,
    const extensions::Extension* app,
    base::OnceCallback<void(bool)> close_callback) {
  NOTIMPLEMENTED_LOG_ONCE();
  if (close_callback) {
    std::move(close_callback).Run(false);
  }
}

void ShowCreateChromeAppShortcutsDialog(
    gfx::NativeWindow parent_window,
    Profile* profile,
    const std::string& web_app_id,
    base::OnceCallback<void(bool)> close_callback) {
  NOTIMPLEMENTED_LOG_ONCE();
  if (close_callback) {
    std::move(close_callback).Run(false);
  }
}

}  // namespace chrome
