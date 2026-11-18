// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_APP_DESKBROWSER_EXTERNAL_DISPLAY_H_
#define IOS_CHROME_APP_DESKBROWSER_EXTERNAL_DISPLAY_H_

#import <UIKit/UIKit.h>

// When an external display is connected, present a fullscreen Chrome
// window on that display using the iPad / regular x regular layout
// (tab strip + full top toolbar). iPhone iOS 27 has no Stage Manager
// and no interactive external-display scene role; the supported API is
// UISceneAccessory.externalNonInteractive plus
// UIWindowSceneSessionRoleExternalDisplayNonInteractive. The phone
// screen becomes a control surface. Real desktop Views/Aura chrome is
// not available on iOS.

#ifdef __cplusplus
extern "C" {
#endif

// Install observers and register the iOS 27 scene accessory once a
// presenter view controller is available. Idempotent. Safe to call
// from the jitless default path at startup.
void DeskBrowserExternalDisplayStart(void);

// If `session` is an external-display role, return the scene
// configuration that instantiates DeskBrowserExternalDisplaySceneDelegate.
// Otherwise return nil so the caller can use Chrome's default
// application-scene configuration.
UISceneConfiguration* DeskBrowserExternalDisplayConfigurationIfNeeded(
    UISceneSession* session);

#ifdef __cplusplus
}
#endif

// Scene delegate instantiated for the external-display session role.
// Named so UIKit can find it from Info.plist and from the accessory
// configuration.
@interface DeskBrowserExternalDisplaySceneDelegate
    : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

#endif  // IOS_CHROME_APP_DESKBROWSER_EXTERNAL_DISPLAY_H_
