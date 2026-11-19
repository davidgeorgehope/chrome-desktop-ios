// Copyright 2016 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "components/reading_list/core/reading_list_pref_names.h"

#include "build/build_config.h"
#include "build/ios_buildflags.h"

namespace reading_list {
namespace prefs {

#if !BUILDFLAG(IS_ANDROID) && !BUILDFLAG(IOS_MOBILE_UI)
// Boolean to track if the first-use experience has been shown on desktop.
const char kReadingListDesktopFirstUseExperienceShown[] =
    "reading_list.desktop_first_use_experience_shown";
#endif  // !BUILDFLAG(IS_ANDROID) && !BUILDFLAG(IOS_MOBILE_UI)

}  // namespace prefs
}  // namespace reading_list
