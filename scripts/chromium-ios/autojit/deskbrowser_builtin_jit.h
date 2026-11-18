// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CONTENT_APP_IOS_DESKBROWSER_BUILTIN_JIT_H_
#define CONTENT_APP_IOS_DESKBROWSER_BUILTIN_JIT_H_

#ifdef __cplusplus
extern "C" {
#endif

// Starts the built-in StikJIT helper (PlugIns/DeskBrowserJITHelper.appex),
// waits until CS_DEBUGGED is set, then enables the TXM prepare hook.
// If attach fails (no pairing file, LocalDevVPN down, or timeout), returns
// false so the caller can stay jitless.
//
// The pairing file is read from Documents/StikJIT/pairingFile.plist (the
// same relative place crate uses). It is never logged. The helper is left
// running so later TXM region prepares can be serviced.
bool DeskBrowserJitEnableWithBuiltInHelper(void);

// If EnableWithBuiltInHelper fell back to jitless, a short reason suitable
// for a one-time on-screen notice. NULL when JIT is on or no notice is
// needed. The pointer is valid for the process lifetime.
const char* DeskBrowserJitFallbackNotice(void);

#ifdef __cplusplus
}
#endif

#endif  // CONTENT_APP_IOS_DESKBROWSER_BUILTIN_JIT_H_
