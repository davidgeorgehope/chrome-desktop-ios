// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CONTENT_APP_IOS_DESKBROWSER_DEVICE_JIT_H_
#define CONTENT_APP_IOS_DESKBROWSER_DEVICE_JIT_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// StikJIT / StikDebug TXM protocol for iOS 26+ (documented in
// StikJIT INTEGRATION.md). These are weak-imported from the Chromium
// binary so V8 can call them without a v8->content GN edge.
//
// On iOS 27 + TXM (A18 Pro), CS_DEBUGGED is not enough: every RX region
// must be prepared with brk #0xf00d / x16=1 before it is executed. A
// writable alias is created with mach_vm_remap. The debugger is left
// attached so later Wasm regions can be prepared too.
//
// If no debugger is attached, DeskBrowserJitTryEnable() returns false
// and the caller should pass --js-flags=--jitless.

void DeskBrowserJitInstallTrapHandler(void);

// Returns true when a debugger is attached (CS_DEBUGGED) and later
// executable allocations can be prepared. Does not fire a brk itself.
bool DeskBrowserJitTryEnable(void);

// True when CS_DEBUGGED is set. Does not log or enable the hook.
bool DeskBrowserJitDebuggerAttached(void);

bool DeskBrowserJitIsEnabled(void);

// After an RX (or MAP_JIT) mapping is created by V8, prepare it and
// record a writable alias. Safe no-op if JIT is not enabled or the
// range was already prepared.
void DeskBrowserJitPrepareRegion(void* addr, size_t size);

// Translate an executable address to the writable alias. Returns |addr|
// unchanged when no alias is registered.
void* DeskBrowserJitWritableAddr(const void* addr);

// Tear down a prepared range (on Free).
void DeskBrowserJitReleaseRegion(void* addr, size_t size);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // CONTENT_APP_IOS_DESKBROWSER_DEVICE_JIT_H_
