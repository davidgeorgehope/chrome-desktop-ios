// Copyright 2013 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/browser_process_platform_part_base.h"

#include "base/notreached.h"
#include "build/build_config.h"
#include "build/ios_buildflags.h"

#if BUILDFLAG(IS_IOS) && BUILDFLAG(ENABLE_IOS_DESKTOP_VIEWS)
// Defined in browser_process_platform_part_ios.mm.
void InitializeIOSGeolocationSystemPermissionManager();
#endif

#if !BUILDFLAG(IS_ANDROID)
#include "chrome/browser/lifetime/application_lifetime_desktop.h"
#endif

BrowserProcessPlatformPartBase::BrowserProcessPlatformPartBase() = default;

BrowserProcessPlatformPartBase::~BrowserProcessPlatformPartBase() = default;

void BrowserProcessPlatformPartBase::StartTearDown() {
}

void BrowserProcessPlatformPartBase::AttemptExit(bool try_to_quit_application) {
// chrome::CloseAllBrowsers() doesn't link on OS_ANDROID, but it overrides this
// method already.
#if BUILDFLAG(IS_ANDROID)
  NOTREACHED();
#else
  // On most platforms, closing all windows causes the application to exit.
  chrome::CloseAllBrowsers();
#endif
}

void BrowserProcessPlatformPartBase::PreMainMessageLoopRun() {
#if BUILDFLAG(IS_IOS) && BUILDFLAG(ENABLE_IOS_DESKTOP_VIEWS)
  // Like Mac (browser_process_platform_part_mac.mm): views such as
  // LocationBarView observe the OS-level geolocation permission manager.
  InitializeIOSGeolocationSystemPermissionManager();
#endif
}

void BrowserProcessPlatformPartBase::PostDestroyThreads() {}
