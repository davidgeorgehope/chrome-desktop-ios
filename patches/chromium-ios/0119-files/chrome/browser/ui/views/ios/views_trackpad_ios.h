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
@interface ChromeViewsIOSTrackpadView : UIView <UIKeyInput>
@end

#endif  // CHROME_BROWSER_UI_VIEWS_IOS_VIEWS_TRACKPAD_IOS_H_
