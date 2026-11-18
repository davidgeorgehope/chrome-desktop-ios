// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_APP_DESKBROWSER_LAUNCHER_H_
#define IOS_CHROME_APP_DESKBROWSER_LAUNCHER_H_

#import <UIKit/UIKit.h>

// Optional JIT launcher (hidden). Icon taps are jitless and skip this
// overlay entirely. The launcher is shown only when the hidden flag
// DESKBROWSER_ENABLE_JIT_LAUNCHER=1, --deskbrowser-enable-jit-launcher,
// or the deskbrowser.enable_jit_launcher default is set. In that mode
// Chrome's AppInitStage still runs past kStart (the foreground CHECK
// requires this) and V8 is deferred at kVariationsSeed until handoff.

#ifdef __cplusplus
extern "C" {
#endif

// YES only after StartIfNeeded() and until handoff. Never holds
// startup unless the launcher was actually presented.
BOOL DeskBrowserLauncherShouldHold(void);

#ifdef __cplusplus
}
#endif

// Default (no hidden flag): force jitless, do not present the overlay,
// and do not start the helper, so an icon tap goes straight into Chrome.
// With the hidden flag, present the overlay and wait for a start choice.
void DeskBrowserLauncherStartIfNeeded(void);

// If the launcher is still holding, stash `advance` and return; it
// is invoked on the main queue at handoff. If already handed off,
// invoke `advance` immediately. Used by AppState to defer the
// kVariationsSeed -> kBrowserObjectsForBackgroundHandlers step.
void DeskBrowserLauncherDeferAdvance(void (^advance)(void));

// Attach the overlay to a newly connected scene window (no-op if
// already handed off or if `window` is nil).
void DeskBrowserLauncherAttachToWindow(UIWindow* window);

#endif  // IOS_CHROME_APP_DESKBROWSER_LAUNCHER_H_
