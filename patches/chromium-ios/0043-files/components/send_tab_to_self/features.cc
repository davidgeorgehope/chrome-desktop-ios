// Copyright 2022 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "components/send_tab_to_self/features.h"

#include "base/feature_list.h"
#include "base/metrics/field_trial_params.h"
#include "base/time/time.h"
#include "build/build_config.h"
#include "build/ios_buildflags.h"

#if BUILDFLAG(IOS_MOBILE_UI)
namespace {

// The default time offset used to pre-populate the date/time picker when the
// 'Set a Reminder' UI half-sheet is first shown.
constexpr base::TimeDelta kReminderNotificationsDefaultOffset = base::Hours(24);

}  // namespace
#endif  // BUILDFLAG(IOS_MOBILE_UI)

namespace send_tab_to_self {

BASE_FEATURE(kSendTabToSelfPropagateNavigationHistory,
             base::FEATURE_DISABLED_BY_DEFAULT);

#if BUILDFLAG(IOS_MOBILE_UI) || BUILDFLAG(IS_ANDROID)
BASE_FEATURE(kSendTabToSelfSupportAutoOpenInTabGrid,
             base::FEATURE_DISABLED_BY_DEFAULT);
#endif  // BUILDFLAG(IOS_MOBILE_UI) || BUILDFLAG(IS_ANDROID)

BASE_FEATURE(kSendTabToSelfEnhancedDesktopUIv2,
             base::FEATURE_DISABLED_BY_DEFAULT);

BASE_FEATURE(kSendTabToSelfSubmenuSigninPromos,
             base::FEATURE_DISABLED_BY_DEFAULT);

BASE_FEATURE(kSendTabToSelfAnchorPromosToProfilePill,
             base::FEATURE_DISABLED_BY_DEFAULT);

BASE_FEATURE(kSendTabToSelfMultiTabShare, base::FEATURE_DISABLED_BY_DEFAULT);

#if BUILDFLAG(IS_ANDROID)
BASE_FEATURE(kSendTabToSelfOpenNativeApp, base::FEATURE_DISABLED_BY_DEFAULT);

BASE_FEATURE(kSendTabToSelfSwitchToParentOnBack,
             base::FEATURE_ENABLED_BY_DEFAULT);
#endif  // BUILDFLAG(IS_ANDROID)

#if BUILDFLAG(IOS_MOBILE_UI)

BASE_FEATURE(kSendTabToSelfIOSShareSheetDeviceList,
             base::FEATURE_DISABLED_BY_DEFAULT);

BASE_FEATURE(kIOSTabReminders, base::FEATURE_DISABLED_BY_DEFAULT);

bool AreIOSTabRemindersEnabled() {
  return base::FeatureList::IsEnabled(kIOSTabReminders);
}

const char kReminderNotificationsDefaultTimeOffset[] =
    "ReminderNotificationsDefaultTimeOffset";

base::TimeDelta GetReminderNotificationsDefaultTimeOffset() {
  // Default to 24 hours.
  return base::GetFieldTrialParamByFeatureAsTimeDelta(
      kIOSTabReminders, kReminderNotificationsDefaultTimeOffset,
      kReminderNotificationsDefaultOffset);
}
#endif  // BUILDFLAG(IOS_MOBILE_UI)

#if BUILDFLAG(IS_ANDROID)
BASE_FEATURE(kSendTabToSelfDynamicShortcuts, base::FEATURE_DISABLED_BY_DEFAULT);
#endif  // BUILDFLAG(IS_ANDROID)

}  // namespace send_tab_to_self
