// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <UIKit/UIKit.h>

#include <functional>

#include "chrome/browser/ui/views/tabs/dragging/window_finder.h"

namespace base::apple {

bool operator<(const WeakUIWindow& a, const WeakUIWindow& b) {
  return std::less<void*>()((__bridge void*)a.Get(), (__bridge void*)b.Get());
}

}  // namespace base::apple
