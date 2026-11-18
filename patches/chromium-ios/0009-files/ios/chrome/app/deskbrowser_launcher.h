// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_APP_DESKBROWSER_LAUNCHER_H_
#define IOS_CHROME_APP_DESKBROWSER_LAUNCHER_H_

#import <UIKit/UIKit.h>

// Crate-style JIT launcher shown as an overlay UIWindow on the scene.
// Chrome's AppInitStage machine is allowed to run past kStart (the
// foreground CHECK requires this). V8 / ContentMain is deferred until
// handoff because the jitless flag must be set before V8 starts.
// The hold is applied at the kVariationsSeed ->
// kBrowserObjectsForBackgroundHandlers transition.

#ifdef __cplusplus
extern "C" {
#endif

// YES only after StartIfNeeded() and until handoff. Never holds
// startup unless the launcher was actually presented.
BOOL DeskBrowserLauncherShouldHold(void);

#ifdef __cplusplus
}
#endif

// Present the overlay and start the built-in JIT helper without
// blocking the main thread. Does not itself advance AppInitStage.
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
