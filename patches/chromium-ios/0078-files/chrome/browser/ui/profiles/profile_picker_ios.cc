// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Desktop Chrome on iOS runs a single profile and has no profile picker
// window (cut; see docs/desktop-chrome-ios-plan.md). These are the
// ProfilePicker statics that ProfilePickerView provides on other platforms.

#include <utility>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/logging.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/ui/profiles/profile_picker.h"

// static
void ProfilePicker::Show(Params&& params) {
  LOG(WARNING) << "Profile picker is not available on iOS; ignoring Show().";
}

// static
void ProfilePicker::SwitchToSignIn(
    ProfileInfo profile_info,
    base::OnceCallback<void(bool)> switch_finished_callback) {
  std::move(switch_finished_callback).Run(false);
}

// static
void ProfilePicker::SwitchToReauth(
    Profile* profile,
    base::OnceCallback<void(bool)> switch_finished_callback,
    base::OnceCallback<void(const ForceSigninUIError&)> on_error_callback) {
  std::move(switch_finished_callback).Run(false);
}

// static
void ProfilePicker::SwitchToSignedOutPostIdentityFlow(
    std::optional<SkColor> profile_color) {}

// static
void ProfilePicker::PickProfile(
    const base::FilePath& profile_path,
    ProfilePickingArgs args,
    base::OnceCallback<void(bool)> pick_profile_complete_callback) {
  std::move(pick_profile_complete_callback).Run(false);
}

// static
void ProfilePicker::CancelSignInFlow() {}

// static
base::FilePath ProfilePicker::GetPickerProfilePath() {
  return ProfileManager::GetSystemProfilePath();
}

// static
void ProfilePicker::Hide() {}

// static
bool ProfilePicker::IsOpen() {
  return false;
}

// static
bool ProfilePicker::IsFirstRunOpen() {
  return false;
}

// static
bool ProfilePicker::IsActive() {
  return false;
}

// static
views::WebView* ProfilePicker::GetWebViewForTesting() {
  return nullptr;
}

// static
views::View* ProfilePicker::GetViewForTesting() {
  return nullptr;
}

// static
void ProfilePicker::AddOnProfilePickerOpenedCallbackForTesting(
    base::OnceClosure callback) {}
