// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// chrome_paths_internal for desktop Views on iOS (ENABLE_IOS_DESKTOP_VIEWS).
// Everything lives in the app sandbox: the profile under
// Library/Application Support/Chromium, user files under Documents.

#include <Foundation/Foundation.h>

#include "base/apple/foundation_util.h"
#include "base/base_paths.h"
#include "base/files/file_path.h"
#include "base/path_service.h"
#include "chrome/common/chrome_paths_internal.h"

namespace chrome {

namespace {

bool GetDocumentsSubdirectory(const char* name, base::FilePath* result) {
  base::FilePath documents;
  if (!base::apple::GetUserDirectory(NSDocumentDirectory, &documents)) {
    return false;
  }
  *result = documents.Append(name);
  return true;
}

}  // namespace

bool GetDefaultUserDataDirectory(base::FilePath* result) {
  base::FilePath app_support;
  if (!base::apple::GetUserDirectory(NSApplicationSupportDirectory,
                                     &app_support)) {
    return false;
  }
  *result = app_support.Append("Chromium");
  return true;
}

bool GetUserDocumentsDirectory(base::FilePath* result) {
  return base::apple::GetUserDirectory(NSDocumentDirectory, result);
}

void GetUserCacheDirectory(const base::FilePath& profile_dir,
                           base::FilePath* result) {
  *result = profile_dir;
  base::FilePath app_data_dir;
  if (!base::PathService::Get(base::DIR_APP_DATA, &app_data_dir)) {
    return;
  }
  base::FilePath cache_dir;
  if (!base::PathService::Get(base::DIR_CACHE, &cache_dir)) {
    return;
  }
  if (!app_data_dir.AppendRelativePath(profile_dir, &cache_dir)) {
    return;
  }
  *result = cache_dir;
}

bool GetUserDownloadsDirectory(base::FilePath* result) {
  return GetDocumentsSubdirectory("Downloads", result);
}

bool GetUserMusicDirectory(base::FilePath* result) {
  return GetDocumentsSubdirectory("Music", result);
}

bool GetUserPicturesDirectory(base::FilePath* result) {
  return GetDocumentsSubdirectory("Pictures", result);
}

bool GetUserVideosDirectory(base::FilePath* result) {
  return GetDocumentsSubdirectory("Videos", result);
}

bool ProcessNeedsProfileDir(const std::string& process_type) {
  return true;
}

}  // namespace chrome
