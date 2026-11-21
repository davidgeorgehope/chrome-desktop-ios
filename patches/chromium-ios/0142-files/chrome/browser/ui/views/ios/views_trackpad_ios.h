// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CHROME_BROWSER_UI_VIEWS_IOS_VIEWS_TRACKPAD_IOS_H_
#define CHROME_BROWSER_UI_VIEWS_IOS_VIEWS_TRACKPAD_IOS_H_

#import <UIKit/UIKit.h>

// Phone-side trackpad for desktop Views Chrome shown on an external display.
// Visible only while an external-display scene is connected. One finger moves
// a cursor on the external display, a tap clicks, two fingers scroll, a
// two-finger tap right-clicks, and keys (hardware or the on-screen keyboard)
// go to the last clicked target: web content or the focused Views control.
//
// A hardware mouse drives the same cursor: GameController (GCMouse) relative
// motion, buttons (press, drag, release; left, right, middle) and the wheel,
// with the phone-side iOS pointer as a fallback and hidden over this view.
//
// With no external display the desktop moves onto the phone's own screen (the
// on-phone desktop): this view turns into a transparent touch layer above it.
// A tap clicks where it lands, a long press or two-finger tap right-clicks,
// one finger scrolls what is under it, and pinch / two-finger drag zoom and
// move the desktop. A hardware mouse and keyboard work as on the monitor.
@interface ChromeViewsIOSTrackpadView
    : UIView <UIKeyInput,
              UIGestureRecognizerDelegate,
              UIPointerInteractionDelegate>
@end

// Interface orientations for the phone scene: the app's usual set with a
// monitor; on the on-phone desktop a tall phone is held in landscape-right
// while a squarer panel (iPhone Duo class) follows the device.
UIInterfaceOrientationMask ChromeViewsIOSPhoneOrientations(void);

#endif  // CHROME_BROWSER_UI_VIEWS_IOS_VIEWS_TRACKPAD_IOS_H_
