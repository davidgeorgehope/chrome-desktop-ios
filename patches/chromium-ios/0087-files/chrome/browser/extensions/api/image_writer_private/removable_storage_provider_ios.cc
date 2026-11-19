// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/extensions/api/image_writer_private/removable_storage_provider.h"

#include "base/memory/scoped_refptr.h"

namespace extensions {

// static
scoped_refptr<StorageDeviceList>
RemovableStorageProvider::PopulateDeviceList() {
  // iOS apps cannot see raw removable block devices, so the list is empty.
  return base::MakeRefCounted<StorageDeviceList>();
}

}  // namespace extensions
