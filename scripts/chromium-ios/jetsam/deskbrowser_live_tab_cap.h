// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_BROWSER_MEMORY_MODEL_DESKBROWSER_LIVE_TAB_CAP_H_
#define IOS_CHROME_BROWSER_MEMORY_MODEL_DESKBROWSER_LIVE_TAB_CAP_H_

// Caps the number of live (not discarded) tabs on the device Blink build and
// restores a discarded tab when it becomes active. Safe to call from the
// UIApplication memory-warning path or from a polling timer; no-ops until
// profiles have been loaded.
void DeskBrowserStartLiveTabCap();
void DeskBrowserEnforceLiveTabCap();

#endif  // IOS_CHROME_BROWSER_MEMORY_MODEL_DESKBROWSER_LIVE_TAB_CAP_H_
