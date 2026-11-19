// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/first_run/first_run_internal.h"

#include "base/files/file_path.h"
#include "base/notimplemented.h"
#include "chrome/browser/first_run/upgrade_util.h"

// The simulator desktop Views host has no installer, importer UI or self-update
// mechanism. UIApplication owns process launch/relaunch.
namespace first_run::internal {

base::FilePath InitialPrefsPath() {
  return base::FilePath();
}

void DoPostImportPlatformSpecificTasks() {}

bool ShowPostInstallEULAIfNeeded(installer::InitialPreferences* install_prefs) {
  return true;
}

}  // namespace first_run::internal

namespace upgrade_util {

bool RelaunchChromeBrowserImpl(const base::CommandLine& command_line) {
  NOTIMPLEMENTED_LOG_ONCE();
  return false;
}

bool IsUpdatePendingRestart() {
  return false;
}

}  // namespace upgrade_util
