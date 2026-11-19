// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/process_singleton.h"

#include "base/memory/ref_counted.h"
#include "base/process/process_handle.h"

// UIKit already guarantees a single instance of the app, so the POSIX socket
// and lock-file singleton is unnecessary on iOS desktop Views.

class ProcessSingleton::LinuxWatcher
    : public base::RefCountedThreadSafe<ProcessSingleton::LinuxWatcher> {
 private:
  friend class base::RefCountedThreadSafe<ProcessSingleton::LinuxWatcher>;
  ~LinuxWatcher() = default;
};

ProcessSingleton::ProcessSingleton(
    const base::FilePath& user_data_dir,
    const NotificationCallback& notification_callback)
    : notification_callback_(notification_callback),
      current_pid_(base::GetCurrentProcId()) {}

ProcessSingleton::~ProcessSingleton() = default;

ProcessSingleton::NotifyResult ProcessSingleton::NotifyOtherProcessOrCreate() {
  return Create() ? PROCESS_NONE : PROFILE_IN_USE;
}

ProcessSingleton::NotifyResult ProcessSingleton::NotifyOtherProcess() {
  return PROCESS_NONE;
}

bool ProcessSingleton::Create() {
  return true;
}

void ProcessSingleton::StartWatching() {}

void ProcessSingleton::Cleanup() {}
