// Copyright 2012 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <UIKit/UIKit.h>

#include <algorithm>
#include <optional>
#include <vector>

#include "base/apple/foundation_util.h"
#include "base/check.h"
#include "base/notimplemented.h"
#include "base/task/single_thread_task_runner.h"
#include "build/ios_buildflags.h"
#include "ui/display/display.h"
#include "ui/display/display_features.h"
#include "ui/display/screen_base.h"
#include "ui/display/util/display_util.h"
#include "ui/gfx/native_ui_types.h"

namespace display {
namespace {
std::optional<gfx::Point> g_cursor_screen_point;

class ScreenNotification {
 public:
  virtual void ScreenChanged() = 0;
};
}  // namespace
}  // namespace display

@interface ScreenObserver : NSObject {
  raw_ptr<display::ScreenNotification, DanglingUntriaged> _notifier;
}
- (void)mainScreenChanged;
@end

@implementation ScreenObserver

- (instancetype)initWithNotifier:(display::ScreenNotification*)notifier {
  if ((self = [super init])) {
    _notifier = notifier;
    NSNotificationCenter* defaultCenter = [NSNotificationCenter defaultCenter];
#if !BUILDFLAG(IS_IOS_TVOS)
    [defaultCenter addObserver:self
                      selector:@selector(mainScreenChanged)
                          name:UIDeviceOrientationDidChangeNotification
                        object:nil];
#endif
    [defaultCenter addObserver:self
                      selector:@selector(mainScreenChanged)
                          name:UIWindowDidBecomeKeyNotification
                        object:nil];
#if BUILDFLAG(ENABLE_IOS_DESKTOP_VIEWS)
    // External displays (TVOut / monitor) arrive and leave as scenes.
    [defaultCenter addObserver:self
                      selector:@selector(mainScreenChanged)
                          name:UISceneWillConnectNotification
                        object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(mainScreenChanged)
                          name:UISceneDidDisconnectNotification
                        object:nil];
#endif
  }

  return self;
}

- (void)mainScreenChanged {
  if (!base::SingleThreadTaskRunner::HasCurrentDefault()) {
    return;
  }
  // This notification comes before UIScreen can change its bounds so post a
  // task so the update occurs after the UIScreen has been updated.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&display::ScreenNotification::ScreenChanged,
                                base::Unretained(_notifier)));
}

@end

namespace display {
namespace {

// Return all screens associated with scenes of the application.
NSArray<UIScreen*>* GetAllActiveScreens() {
#if BUILDFLAG(IS_IOS_APP_EXTENSION)
  return [NSArray<UIScreen*> array];
#else
  NSMutableSet<UIScreen*>* screens = [NSMutableSet set];
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    auto* window_scene = base::apple::ObjCCast<UIWindowScene>(scene);
    if (!window_scene) {
      continue;
    }
    for (UIWindow* window in window_scene.windows) {
      if (UIScreen* screen = window.screen) {
        [screens addObject:screen];
      }
    }
    // A connecting scene may not have windows yet; UIWindowScene.screen
    // is still valid and is needed before the first Views widget exists.
    if (UIScreen* screen = window_scene.screen) {
      [screens addObject:screen];
    }
  }
  if (screens.count == 0) {
    if (UIScreen* main = UIScreen.mainScreen) {
      [screens addObject:main];
    }
  }
  return [screens allObjects];
#endif
}

class ScreenIos : public ScreenBase, public ScreenNotification {
 public:
  ScreenIos() {
    observer_ = [[ScreenObserver alloc] initWithNotifier:this];
    ScreenChanged();
  }

  ScreenIos(const ScreenIos&) = delete;
  ScreenIos& operator=(const ScreenIos&) = delete;

  void ScreenChanged() override {
#if BUILDFLAG(ENABLE_IOS_DESKTOP_VIEWS)
    DesktopViewsScreensChanged();
#else
    MobileScreenChanged();
#endif
  }

  void MobileScreenChanged() {
    UIScreen* screen = GetAllActiveScreens().firstObject;
    if (!screen) {
      return;
    }

    const int64_t display_id = 0;
    Display display(display_id, gfx::Rect(screen.bounds));
    CGFloat scale = [screen scale];

    if (Display::HasForceDeviceScaleFactor()) {
      scale = Display::GetForcedDeviceScaleFactor();
    }
    display.set_device_scale_factor(scale);

#if !BUILDFLAG(IS_IOS_TVOS)
    Display::Rotation rotation = Display::ROTATE_0;
    switch (UIDevice.currentDevice.orientation) {
      case UIDeviceOrientationPortrait:
      case UIDeviceOrientationFaceUp:
      case UIDeviceOrientationFaceDown:
      case UIDeviceOrientationUnknown:
        rotation = Display::ROTATE_0;
        break;
      case UIDeviceOrientationPortraitUpsideDown:
        rotation = Display::ROTATE_180;
        break;
      case UIDeviceOrientationLandscapeLeft:
        rotation = Display::ROTATE_90;
        break;
      case UIDeviceOrientationLandscapeRight:
        rotation = Display::ROTATE_270;
        break;
    }
    display.set_rotation(rotation);
    display.set_touch_support(Display::TouchSupport::AVAILABLE);
    display.set_accelerometer_support(Display::AccelerometerSupport::AVAILABLE);
    AddInternalDisplayId(display_id);
#endif

    ProcessDisplayChanged(display, true /* is_primary */);
  }

#if BUILDFLAG(ENABLE_IOS_DESKTOP_VIEWS)
  // Desktop Chrome Views on iOS: one Display per UIScreen. An external
  // screen (the monitor the browser window lives on) is the primary display
  // at the origin, as a desktop's main monitor would be; the phone panel sits
  // to its right. NativeWidgetIOS frames windows in their screen's own
  // coordinates, which match for the primary display.
  static constexpr int64_t kPanelDisplayId = 0;
  static constexpr int64_t kExternalDisplayIdBase = 1;

  int64_t DisplayIdForScreen(UIScreen* screen) const {
    if (!screen || screen == UIScreen.mainScreen) {
      return kPanelDisplayId;
    }
    NSUInteger index = [UIScreen.screens indexOfObject:screen];
    return kExternalDisplayIdBase +
           (index == NSNotFound ? 0 : static_cast<int64_t>(index));
  }

  void DesktopViewsScreensChanged() {
    NSArray<UIScreen*>* screens = GetAllActiveScreens();
    UIScreen* primary = nil;
    for (UIScreen* screen in screens) {
      if (screen != UIScreen.mainScreen) {
        primary = screen;
        break;
      }
    }
    if (!primary) {
      primary = screens.firstObject;
    }
    if (!primary) {
      return;
    }
    std::vector<int64_t> live_ids;
    int x_offset = static_cast<int>(primary.bounds.size.width);
    for (UIScreen* screen in screens) {
      const int64_t id = DisplayIdForScreen(screen);
      live_ids.push_back(id);
      gfx::Rect bounds(gfx::Size(screen.bounds.size.width,
                                 screen.bounds.size.height));
      if (screen != primary) {
        bounds.set_x(x_offset);
        x_offset += bounds.width();
      }
      Display display(id, bounds);
      display.set_device_scale_factor(Display::HasForceDeviceScaleFactor()
                                          ? Display::GetForcedDeviceScaleFactor()
                                          : screen.scale);
      if (screen == UIScreen.mainScreen) {
        display.set_touch_support(Display::TouchSupport::AVAILABLE);
        AddInternalDisplayId(id);
      }
      ProcessDisplayChanged(display, screen == primary);
    }
    std::vector<int64_t> stale_ids;
    for (const Display& display : display_list().displays()) {
      if (std::find(live_ids.begin(), live_ids.end(), display.id()) ==
          live_ids.end()) {
        stale_ids.push_back(display.id());
      }
    }
    for (int64_t id : stale_ids) {
      display_list().RemoveDisplay(id);
    }
  }

  Display GetDisplayNearestWindow(gfx::NativeWindow window) const override {
    UIWindow* uiwindow = window.Get();
    auto it = display_list().FindDisplayById(
        DisplayIdForScreen(uiwindow ? uiwindow.screen : nil));
    return it != display_list().displays().end() ? *it : GetPrimaryDisplay();
  }

  Display GetDisplayNearestView(gfx::NativeView view) const override {
    UIView* uiview = view.Get();
    return GetDisplayNearestWindow(gfx::NativeWindow(uiview ? uiview.window
                                                            : nil));
  }

  // No hover cursor unless a pointer is attached; report the primary
  // display's center instead of logging on every call.
  gfx::Point GetCursorScreenPoint() override {
    return g_cursor_screen_point.value_or(
        GetPrimaryDisplay().bounds().CenterPoint());
  }
#else
  gfx::Point GetCursorScreenPoint() override {
    NOTIMPLEMENTED();
    return gfx::Point(0, 0);
  }
#endif

  bool IsWindowUnderCursor(gfx::NativeWindow window) override {
    return window && GetWindowAtScreenPoint(GetCursorScreenPoint()) == window;
  }

  gfx::NativeWindow GetWindowAtScreenPoint(const gfx::Point& point) override {
#if BUILDFLAG(ENABLE_IOS_DESKTOP_VIEWS)
    // Screen coordinates include the panel's desktop offset. UIKit window
    // frames instead use coordinates local to their own UIScreen.
    const Display display = GetDisplayNearestPoint(point);
    if (!display.bounds().Contains(point)) {
      return gfx::NativeWindow();
    }
    CGPoint local = CGPointMake(point.x() - display.bounds().x(),
                                point.y() - display.bounds().y());
    UIWindow* front = nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
      if (![scene isKindOfClass:[UIWindowScene class]]) {
        continue;
      }
      UIWindowScene* ws = (UIWindowScene*)scene;
      if (DisplayIdForScreen(ws.screen) != display.id() ||
          ws.activationState == UISceneActivationStateBackground ||
          ws.activationState == UISceneActivationStateUnattached) {
        continue;
      }
      // UIKit lists a scene's windows back-to-front. Later windows at the
      // same level win, while non-interactive cursor overlays are ignored.
      for (UIWindow* window in ws.windows) {
        if (window.hidden || window.alpha <= 0.01 ||
            !window.userInteractionEnabled) {
          continue;
        }
        CGPoint p = [window convertPoint:local
                   fromCoordinateSpace:ws.screen.coordinateSpace];
        if (!CGRectContainsPoint(window.bounds, p) ||
            ![window hitTest:p withEvent:nil]) {
          continue;
        }
        if (!front || window.windowLevel >= front.windowLevel) {
          front = window;
        }
      }
    }
    return gfx::NativeWindow(front);
#else
    return gfx::NativeWindow();
#endif
  }

  int GetNumDisplays() const override {
    return std::max(static_cast<int>([GetAllActiveScreens() count]), 1);
  }

 private:
  ScreenObserver* __strong observer_;
};

}  // namespace

void UpdateCursorScreenPointForIOS(const gfx::Point& point) {
  g_cursor_screen_point = point;
}

// static
gfx::NativeWindow Screen::GetWindowForView(gfx::NativeView view) {
  return gfx::NativeWindow(view.Get().window);
}

Screen* CreateNativeScreen() {
  return new ScreenIos;
}

float GetInternalDisplayDeviceScaleFactor() {
#if BUILDFLAG(IS_IOS_APP_EXTENSION)
  return 1.0f;
#else
  UIScreen* screen = GetAllActiveScreens().firstObject;
  return screen ? screen.scale : 1.0f;
#endif
}

}  // namespace display
