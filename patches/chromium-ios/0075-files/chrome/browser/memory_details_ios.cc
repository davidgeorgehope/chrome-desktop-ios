// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/memory_details.h"

#include <vector>

#include "base/functional/bind.h"
#include "base/process/process_handle.h"
#include "base/strings/utf_string_conversions.h"
#include "base/threading/scoped_blocking_call.h"
#include "components/version_info/version_info.h"
#include "content/public/browser/browser_task_traits.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/common/process_type.h"

// iOS desktop Views runs browser, renderer and GPU in one app process (no
// helper executables to enumerate), so report the child info content gives us.

MemoryDetails::MemoryDetails() {
  ProcessData process;
  process.name = base::ASCIIToUTF16(version_info::GetProductName());
  process.process_name = process.name;
  process_data_.push_back(process);
}

ProcessData* MemoryDetails::ChromeBrowser() {
  return &process_data_[0];
}

void MemoryDetails::CollectProcessData(
    const std::vector<ProcessMemoryInformation>& child_info) {
  base::ScopedBlockingCall scoped_blocking_call(FROM_HERE,
                                                base::BlockingType::MAY_BLOCK);
  ProcessMemoryInformationList& processes = process_data_[0].processes;
  processes.clear();

  ProcessMemoryInformation browser;
  browser.pid = base::GetCurrentProcId();
  browser.process_type = content::PROCESS_TYPE_BROWSER;
  processes.push_back(browser);
  for (const ProcessMemoryInformation& child : child_info) {
    if (child.pid != browser.pid) {
      processes.push_back(child);
    }
  }

  content::GetUIThreadTaskRunner({})->PostTask(
      FROM_HERE,
      base::BindOnce(&MemoryDetails::CollectChildInfoOnUIThread, this));
}
