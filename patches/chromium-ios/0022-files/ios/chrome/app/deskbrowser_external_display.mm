// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/chrome/app/deskbrowser_external_display.h"

// Implemented on RenderWidgetUIView / CALayerFrameSinkProvider.
@interface UIView (DeskBrowserExternalInput)
- (void)deskBrowserRebindLayerHierarchyAfterMovingWindows;
- (void)deskBrowserInjectMouseAtViewPoint:(CGPoint)point
                                     type:(NSInteger)type
                                   button:(NSInteger)button;
- (void)deskBrowserInjectWheelAtViewPoint:(CGPoint)point
                                    delta:(CGPoint)delta
                                    phase:(NSInteger)phase;
@end


namespace {

NSString* const kExternalSceneConfigurationName =
    @"DeskBrowser External Display";

id g_accessory_registration = nil;
__weak UIViewController* g_accessory_presenter = nil;
BOOL g_legacy_mirror_window = NO;
BOOL g_started = NO;
BOOL g_observing = NO;
NSTimer* g_attach_timer = nil;
UIWindow* g_external_window = nil;
UIViewController* g_hosted_chrome_vc = nil;
UIViewController* g_control_surface_vc = nil;
__weak UIWindow* g_phone_window = nil;
UIWindow* g_cursor_window = nil;
UIView* g_cursor_view = nil;
CGPoint g_cursor_point = {0, 0};
BOOL g_cursor_button_down = NO;

NSString* ClassName(id object) {
  return object ? NSStringFromClass([object class]) : @"nil";
}

// Unified logs redact %@ for C-string-looking objects from the app.
// Print sizes and class names as plain UTF-8 so they stay visible.
const char* Pub(NSString* value) {
  return value ? value.UTF8String : "nil";
}

NSString* SizeStr(CGSize size) {
  return [NSString stringWithFormat:@"%.0fx%.0f", size.width, size.height];
}

NSString* RectStr(CGRect rect) {
  return [NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f", rect.origin.x,
          rect.origin.y, rect.size.width, rect.size.height];
}

BOOL ViewControllerTreeLooksLikeChrome(UIViewController* vc) {
  if (!vc) {
    return NO;
  }
  NSString* name = ClassName(vc);
  // Chrome's browser UI, including iPad layout containers and the tab
  // grid. Avoid matching the launch storyboard or our own control
  // surface.
  if ([name containsString:@"BrowserViewController"] ||
      [name containsString:@"BrowserCoordinator"] ||
      [name containsString:@"BrowserLayout"] ||
      [name containsString:@"TabGridViewController"] ||
      [name containsString:@"TabStrip"]) {
    return YES;
  }
  for (UIViewController* child in vc.childViewControllers) {
    if (ViewControllerTreeLooksLikeChrome(child)) {
      return YES;
    }
  }
  if (vc.presentedViewController &&
      ViewControllerTreeLooksLikeChrome(vc.presentedViewController)) {
    return YES;
  }
  return NO;
}

BOOL IsControlSurface(UIViewController* vc) {
  return vc && [ClassName(vc) isEqualToString:@"DeskBrowserExternalControlSurfaceViewController"];
}

BOOL RoleEquals(UISceneSessionRole role, UISceneSessionRole expected) {
  return role && expected && [role isEqualToString:expected];
}

UIWindow* PrimaryApplicationWindow(void) {
  UIWindow* app_fallback = nil;
  UIWindow* any_fallback = nil;
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    UIWindowScene* window_scene = (UIWindowScene*)scene;
    if (![window_scene isKindOfClass:[UIWindowScene class]]) {
      continue;
    }
    BOOL is_app = RoleEquals(window_scene.session.role,
                             UIWindowSceneSessionRoleApplication);
    for (UIWindow* window in window_scene.windows) {
      if (window == g_external_window) {
        continue;
      }
      if (is_app && window.isKeyWindow) {
        return window;
      }
      if (is_app && !app_fallback) {
        app_fallback = window;
      }
      if (!any_fallback) {
        any_fallback = window;
      }
    }
  }
  if (app_fallback) {
    return app_fallback;
  }
  if (any_fallback) {
    return any_fallback;
  }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  for (UIWindow* window in UIApplication.sharedApplication.windows) {
    if (window != g_external_window) {
      return window;
    }
  }
#pragma clang diagnostic pop
  return nil;
}

void ForceRegularSizeClass(UIWindow* window);
void ClearSizeClassOverrides(UIViewController* vc);

void SyncExternalWindowFrame(UIWindowScene* window_scene, UIWindow* window) {
  if (!window_scene || !window) {
    return;
  }
  // Do not switch screen.currentMode on the official iOS 27 external
  // scene; the system ignored it and a mode change is a plausible
  // way to bounce the scene.
  CGRect bounds = window_scene.coordinateSpace.bounds;
  if (CGRectIsEmpty(bounds) || bounds.size.width < 2 || bounds.size.height < 2) {
    bounds = window_scene.screen.bounds;
  }
  if (!CGRectEqualToRect(window.frame, bounds)) {
    NSLog(@"deskbrowser-external: official window frame %s -> %s",
          Pub(RectStr(window.frame)), Pub(RectStr(bounds)));
  }
  window.frame = bounds;
  if (window.rootViewController) {
    window.rootViewController.view.frame = window.bounds;
  }
  ForceRegularSizeClass(window);
}

void ForceRegularSizeClass(UIWindow* window) {
  if (!window) {
    return;
  }
  window.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassRegular;
  window.traitOverrides.verticalSizeClass = UIUserInterfaceSizeClassRegular;
  UIViewController* root = window.rootViewController;
  if (root) {
    root.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassRegular;
    root.traitOverrides.verticalSizeClass = UIUserInterfaceSizeClassRegular;
  }
}


void ClearSizeClassOverrides(UIViewController* vc) {
  if (!vc) {
    return;
  }
  vc.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassUnspecified;
  vc.traitOverrides.verticalSizeClass = UIUserInterfaceSizeClassUnspecified;
}



UIView* FindRenderWidgetView(UIView* view) {
  if (!view) {
    return nil;
  }
  if ([NSStringFromClass(view.class) isEqualToString:@"RenderWidgetUIView"]) {
    return view;
  }
  for (UIView* sub in view.subviews) {
    if (UIView* found = FindRenderWidgetView(sub)) {
      return found;
    }
  }
  return nil;
}

void RebindCompositorViews(UIView* view) {
  if (!view) {
    return;
  }
  if ([view respondsToSelector:@selector(
                                   deskBrowserRebindLayerHierarchyAfterMovingWindows)]) {
    [view deskBrowserRebindLayerHierarchyAfterMovingWindows];
  }
  for (UIView* sub in view.subviews) {
    RebindCompositorViews(sub);
  }
}

void HideCursor(void) {
  g_cursor_window.hidden = YES;
  g_cursor_window = nil;
  g_cursor_view = nil;
  g_cursor_button_down = NO;
}

void ShowOrUpdateCursor(void) {
  if (!g_external_window || !g_external_window.windowScene) {
    HideCursor();
    return;
  }
  if (!g_cursor_window ||
      g_cursor_window.windowScene != g_external_window.windowScene) {
    HideCursor();
    UIWindow* cursor_window =
        [[UIWindow alloc] initWithWindowScene:g_external_window.windowScene];
    cursor_window.frame = g_external_window.bounds;
    cursor_window.windowLevel = UIWindowLevelAlert + 1;
    cursor_window.backgroundColor = [UIColor clearColor];
    cursor_window.userInteractionEnabled = NO;
    cursor_window.hidden = NO;
    g_cursor_window = cursor_window;
    UIView* cursor = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 22, 22)];
    cursor.userInteractionEnabled = NO;
    cursor.layer.cornerRadius = 11;
    cursor.layer.borderWidth = 1.5;
    cursor.layer.borderColor = [UIColor blackColor].CGColor;
    cursor.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.92];
    cursor.layer.shadowColor = [UIColor blackColor].CGColor;
    cursor.layer.shadowOpacity = 0.45;
    cursor.layer.shadowRadius = 2;
    cursor.layer.shadowOffset = CGSizeMake(0, 1);
    [cursor_window addSubview:cursor];
    g_cursor_view = cursor;
    if (CGPointEqualToPoint(g_cursor_point, CGPointZero)) {
      g_cursor_point = CGPointMake(CGRectGetMidX(g_external_window.bounds),
                                   CGRectGetMidY(g_external_window.bounds));
    }
  }
  g_cursor_window.frame = g_external_window.bounds;
  CGRect bounds = g_external_window.bounds;
  g_cursor_point.x = MIN(MAX(g_cursor_point.x, 0), CGRectGetMaxX(bounds) - 1);
  g_cursor_point.y = MIN(MAX(g_cursor_point.y, 0), CGRectGetMaxY(bounds) - 1);
  g_cursor_view.center = g_cursor_point;
  g_cursor_window.hidden = NO;
}

UIView* HostedRenderWidget(void) {
  return g_hosted_chrome_vc ? FindRenderWidgetView(g_hosted_chrome_vc.view)
                            : nil;
}

void InjectMouseToHostedChrome(NSInteger type, NSInteger button) {
  UIView* widget = HostedRenderWidget();
  if (!widget || !g_external_window) {
    return;
  }
  CGPoint in_widget =
      [widget convertPoint:g_cursor_point fromView:g_external_window];
  if ([widget respondsToSelector:@selector(deskBrowserInjectMouseAtViewPoint:
                                                                     type:
                                                                   button:)]) {
    [widget deskBrowserInjectMouseAtViewPoint:in_widget
                                         type:type
                                       button:button];
  }
}

void InjectWheelToHostedChrome(CGPoint delta, NSInteger phase) {
  UIView* widget = HostedRenderWidget();
  if (!widget || !g_external_window) {
    return;
  }
  CGPoint in_widget =
      [widget convertPoint:g_cursor_point fromView:g_external_window];
  if ([widget respondsToSelector:@selector(deskBrowserInjectWheelAtViewPoint:
                                                                      delta:
                                                                      phase:)]) {
    [widget deskBrowserInjectWheelAtViewPoint:in_widget
                                        delta:delta
                                        phase:phase];
  }
}

void FocusWebContentOnExternalWindow(void) {
  if (!g_external_window) {
    return;
  }
  [g_external_window makeKeyAndVisible];
  UIView* widget = HostedRenderWidget();
  if (widget) {
    [widget becomeFirstResponder];
  }
}

void RebindAndFocusExternalChrome(void) {
  if (!g_external_window || !g_hosted_chrome_vc) {
    return;
  }
  [g_hosted_chrome_vc.view setNeedsLayout];
  [g_hosted_chrome_vc.view layoutIfNeeded];
  RebindCompositorViews(g_hosted_chrome_vc.view);
  ShowOrUpdateCursor();
  FocusWebContentOnExternalWindow();
}

void PlaceChromeOnExternalDisplay(void) {
  UIWindow* phone = PrimaryApplicationWindow();
  if (!phone || !g_external_window) {
    return;
  }
  g_phone_window = phone;

  UIViewController* phone_root = phone.rootViewController;
  if (!phone_root) {
    return;
  }

  // Chrome sometimes replaces the phone root after we have already
  // moved an earlier controller. Steal the new one.
  if (IsControlSurface(phone_root)) {
    if (g_hosted_chrome_vc &&
        g_external_window.rootViewController == g_hosted_chrome_vc) {
      ForceRegularSizeClass(g_external_window);
      return;
    }
  }

  if (!ViewControllerTreeLooksLikeChrome(phone_root)) {
    return;
  }

  if (phone_root == g_external_window.rootViewController) {
    ForceRegularSizeClass(g_external_window);
    return;
  }

  if (CGRectIsEmpty(g_external_window.bounds) ||
      g_external_window.bounds.size.width < 2 ||
      g_external_window.bounds.size.height < 2) {
    NSLog(@"deskbrowser-external: official window has empty bounds %s; "
          @"waiting to move chrome",
          Pub(SizeStr(g_external_window.bounds.size)));
    return;
  }

  NSLog(@"deskbrowser-external: moving %s onto the official external display "
        @"(%s)",
        Pub(ClassName(phone_root)),
        Pub(SizeStr(g_external_window.bounds.size)));

  g_hosted_chrome_vc = phone_root;
  // Detach from the phone window before attaching to the monitor.
  phone.rootViewController = nil;

  if (!g_control_surface_vc) {
    Class control_class =
        NSClassFromString(@"DeskBrowserExternalControlSurfaceViewController");
    g_control_surface_vc = [[control_class alloc] init];
  }
  phone.rootViewController = g_control_surface_vc;

  g_hosted_chrome_vc.view.frame = g_external_window.bounds;
  g_hosted_chrome_vc.view.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  g_external_window.rootViewController = g_hosted_chrome_vc;
  ForceRegularSizeClass(g_external_window);
  g_external_window.hidden = NO;
  [g_external_window layoutIfNeeded];
  [g_external_window makeKeyAndVisible];
  RebindAndFocusExternalChrome();
  // A second pass after the next run-loop turn, once UIKit has a
  // non-zero render-server context for the new scene.
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        RebindAndFocusExternalChrome();
      });
  // Phone stays visible as the trackpad / keyboard surface.
  [phone setHidden:NO];
}

void RestoreChromeToPhoneIfNeeded(void) {
  if (!g_hosted_chrome_vc) {
    return;
  }
  UIWindow* phone = g_phone_window ?: PrimaryApplicationWindow();
  NSLog(@"deskbrowser-external: restoring %s to the phone",
        Pub(ClassName(g_hosted_chrome_vc)));
  HideCursor();
  if (g_external_window &&
      g_external_window.rootViewController == g_hosted_chrome_vc) {
    g_external_window.rootViewController = nil;
  }
  if (phone) {
    ClearSizeClassOverrides(g_hosted_chrome_vc);
    phone.rootViewController = g_hosted_chrome_vc;
    [phone makeKeyAndVisible];
  }
  g_hosted_chrome_vc = nil;
  g_control_surface_vc = nil;
}

UIViewController* FirstAttachedController(UIViewController* vc) {
  if (!vc) {
    return nil;
  }
  // Force the view to load so a just-attached root VC can enter a window.
  UIView* view = vc.view;
  if (view && view.window) {
    return vc;
  }
  for (UIViewController* child in vc.childViewControllers) {
    if (UIViewController* found = FirstAttachedController(child)) {
      return found;
    }
  }
  if (vc.presentedViewController) {
    if (UIViewController* found =
            FirstAttachedController(vc.presentedViewController)) {
      return found;
    }
  }
  return view ? vc : nil;
}

UIViewController* PresenterViewController(void) {
  NSMutableArray<UIWindow*>* windows = [NSMutableArray array];
  UIWindow* primary = PrimaryApplicationWindow();
  if (primary) {
    [windows addObject:primary];
  }
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    UIWindowScene* window_scene = (UIWindowScene*)scene;
    if (![window_scene isKindOfClass:[UIWindowScene class]]) {
      continue;
    }
    for (UIWindow* window in window_scene.windows) {
      if (window == g_external_window) {
        continue;
      }
      if (![windows containsObject:window]) {
        [windows addObject:window];
      }
    }
  }
  for (UIWindow* window in windows) {
    UIViewController* root = window.rootViewController;
    if (!root) {
      continue;
    }
    while (root.presentedViewController) {
      root = root.presentedViewController;
    }
    if (IsControlSurface(root)) {
      continue;
    }
    if (UIViewController* attached = FirstAttachedController(root)) {
      return attached;
    }
  }
  return nil;
}

UISceneConfiguration* ExternalSceneConfiguration(void) {
  UISceneConfiguration* config = [[UISceneConfiguration alloc]
      initWithName:kExternalSceneConfigurationName
      sessionRole:UIWindowSceneSessionRoleExternalDisplayNonInteractive];
  config.delegateClass = [DeskBrowserExternalDisplaySceneDelegate class];
  config.sceneClass = [UIWindowScene class];
  return config;
}

void UnregisterAccessory(void) {
#if defined(__IPHONE_27_0)
  if (@available(iOS 27.0, *)) {
    if (g_accessory_registration && g_accessory_presenter) {
      [g_accessory_presenter
          unregisterSceneAccessory:(UISceneAccessoryRegistration*)
                                       g_accessory_registration];
    }
  }
#endif
  g_accessory_registration = nil;
  g_accessory_presenter = nil;
}

void RegisterAccessoryIfPossible(void) {
#if defined(__IPHONE_27_0)
  if (@available(iOS 27.0, *)) {
    UIViewController* presenter = PresenterViewController();
    // The control surface is only on the phone after we have already
    // taken over the external display; do not register on it.
    if (IsControlSurface(presenter)) {
      presenter = nil;
    }

    if (g_accessory_registration) {
      UIViewController* previous = g_accessory_presenter;
      BOOL previous_still_valid =
          previous && previous.viewIfLoaded.window &&
          (!presenter || presenter == previous);
      if (previous_still_valid) {
        UISceneAccessoryRegistration* registration =
            (UISceneAccessoryRegistration*)g_accessory_registration;
        registration.enabled = YES;
        static CFAbsoluteTime last_log = 0;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - last_log > 5) {
          last_log = now;
          NSLog(@"deskbrowser-external: accessory available=%d enabled=%d "
                @"presenter=%s",
                registration.isAvailable, registration.isEnabled,
                Pub(ClassName(previous)));
        }
        return;
      }
      NSLog(@"deskbrowser-external: presenter changed (%s -> %s); "
            @"re-registering accessory",
            Pub(ClassName(previous)), Pub(ClassName(presenter)));
      UnregisterAccessory();
    }

    if (!presenter || !presenter.view.window) {
      static CFAbsoluteTime last_skip_log = 0;
      CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
      if (now - last_skip_log > 5) {
        last_skip_log = now;
        UIWindow* phone = PrimaryApplicationWindow();
        NSLog(@"deskbrowser-external: accessory not registered "
              @"(window=%s key=%d root=%s presenter=%s view.window=%s "
              @"scenes=%lu)",
              phone ? "Y" : "N", phone.isKeyWindow,
              Pub(ClassName(phone.rootViewController)),
              Pub(ClassName(presenter)),
              presenter.viewIfLoaded.window ? "Y" : "N",
              (unsigned long)UIApplication.sharedApplication.connectedScenes.count);
      }
      return;
    }

    UISceneAccessory* accessory = [UISceneAccessory
        externalNonInteractiveSceneAccessoryWithConfiguration:
            ExternalSceneConfiguration()];
    UISceneAccessoryRegistration* registration =
        [presenter registerSceneAccessory:accessory];
    if (!registration) {
      NSLog(@"deskbrowser-external: registerSceneAccessory returned nil on %s",
            Pub(ClassName(presenter)));
      return;
    }
    registration.enabled = YES;
    g_accessory_registration = registration;
    g_accessory_presenter = presenter;
    NSLog(@"deskbrowser-external: registered iOS 27 scene accessory on %s "
          @"available=%d",
          Pub(ClassName(presenter)), registration.isAvailable);
  }
#endif
}

BOOL HasExternalSceneWindow(void) {
  if (!g_external_window) {
    return NO;
  }
  UIWindowScene* scene = g_external_window.windowScene;
  if (scene) {
    UISceneSessionRole role = scene.session.role;
    if (RoleEquals(role, UIWindowSceneSessionRoleExternalDisplayNonInteractive) ||
        RoleEquals(role, UIWindowSceneSessionRoleExternalDisplay)) {
      return YES;
    }
  }
  return NO;
}

void LogDisplayStateOnceInAWhile(void) {
  static CFAbsoluteTime last_log = 0;
  CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
  if (now - last_log < 5) {
    return;
  }
  last_log = now;
  NSMutableArray<NSString*>* screens = [NSMutableArray array];
  for (UIScreen* screen in UIScreen.screens) {
    [screens addObject:[NSString
                           stringWithFormat:@"bounds=%@ mirrored=%s scale=%.1f",
                                            RectStr(screen.bounds),
                                            screen.mirroredScreen ? "Y" : "N",
                                            screen.scale]];
  }
  NSMutableArray<NSString*>* roles = [NSMutableArray array];
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
      [roles addObject:((UIWindowScene*)scene).session.role];
    }
  }
  NSLog(@"deskbrowser-external: screens=[%s] mirrored=%s scenes=[%s] "
        @"legacy=%d extWin=%s",
        Pub([screens componentsJoinedByString:@"; "]),
        UIScreen.mainScreen.mirroredScreen ? "Y" : "N",
        Pub([roles componentsJoinedByString:@","]),
        g_legacy_mirror_window, g_external_window ? "Y" : "N");
}

void AttachTimerTick(void) {
  LogDisplayStateOnceInAWhile();
  RegisterAccessoryIfPossible();
  // Official-scene only. The legacy UIScreen / mirroredScreen takeover
  // raced the iOS 27 ExternalDisplayNonInteractive scene (it moved the
  // browser VC first; CoreAnimation then logged "cannot add handler to
  // 0 from 0") and re-claimed the display after the official scene
  // disconnected, leaving a blank window. On disconnect we restore
  // Chrome to the phone and wait for the official scene to reconnect.
  if (HasExternalSceneWindow()) {
    if (g_external_window.windowScene) {
      SyncExternalWindowFrame(g_external_window.windowScene,
                              g_external_window);
    }
    PlaceChromeOnExternalDisplay();
  }
}

}  // namespace

#pragma mark - Control surface

@interface DeskBrowserExternalControlSurfaceViewController : UIViewController
@end

@implementation DeskBrowserExternalControlSurfaceViewController {
  NSInteger _scroll_phase;  // -1 idle, 0 began, 1 changed
}

- (void)viewDidLoad {
  [super viewDidLoad];
  _scroll_phase = -1;
  self.view.backgroundColor = [UIColor colorWithRed:0.13
                                              green:0.14
                                               blue:0.16
                                               alpha:1.0];
  self.view.multipleTouchEnabled = YES;

  UILabel* title = [[UILabel alloc] init];
  title.text = @"Trackpad for your monitor";
  title.textColor = [UIColor whiteColor];
  title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightSemibold];
  title.textAlignment = NSTextAlignmentCenter;
  title.numberOfLines = 0;
  title.translatesAutoresizingMaskIntoConstraints = NO;

  UILabel* body = [[UILabel alloc] init];
  body.text = @"Chrome is on the connected display.\n\n"
              @"Move one finger to drive the cursor.\n"
              @"Tap to click. Two-finger drag to scroll.\n\n"
              @"A keyboard paired with this iPhone types in "
              @"the window on the monitor.\n\n"
              @"Unplug the monitor to bring Chrome back here.";
  body.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
  body.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
  body.textAlignment = NSTextAlignmentCenter;
  body.numberOfLines = 0;
  body.translatesAutoresizingMaskIntoConstraints = NO;

  UIView* pad = [[UIView alloc] init];
  pad.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
  pad.layer.cornerRadius = 22;
  pad.translatesAutoresizingMaskIntoConstraints = NO;
  pad.multipleTouchEnabled = YES;
  pad.userInteractionEnabled = YES;

  UILabel* pad_hint = [[UILabel alloc] init];
  pad_hint.text = @"Trackpad";
  pad_hint.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
  pad_hint.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
  pad_hint.textAlignment = NSTextAlignmentCenter;
  pad_hint.translatesAutoresizingMaskIntoConstraints = NO;
  pad_hint.userInteractionEnabled = NO;
  [pad addSubview:pad_hint];

  UIStackView* stack =
      [[UIStackView alloc] initWithArrangedSubviews:@[ title, body, pad ]];
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 16;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                        constant:24],
    [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                         constant:-24],
    [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                                    constant:20],
    [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor
                                       constant:-20],
    [pad_hint.centerXAnchor constraintEqualToAnchor:pad.centerXAnchor],
    [pad_hint.centerYAnchor constraintEqualToAnchor:pad.centerYAnchor],
  ]];
  [pad setContentHuggingPriority:UILayoutPriorityDefaultLow
                         forAxis:UILayoutConstraintAxisVertical];
  [title setContentHuggingPriority:UILayoutPriorityRequired
                           forAxis:UILayoutConstraintAxisVertical];
  [body setContentHuggingPriority:UILayoutPriorityRequired
                          forAxis:UILayoutConstraintAxisVertical];

  UIPanGestureRecognizer* move = [[UIPanGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handleMove:)];
  move.maximumNumberOfTouches = 1;
  move.allowedTouchTypes = @[ @(UITouchTypeDirect) ];
  [pad addGestureRecognizer:move];

  UIPanGestureRecognizer* scroll = [[UIPanGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handleScroll:)];
  scroll.minimumNumberOfTouches = 2;
  scroll.maximumNumberOfTouches = 2;
  [pad addGestureRecognizer:scroll];

  UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handleTap:)];
  tap.numberOfTapsRequired = 1;
  tap.numberOfTouchesRequired = 1;
  [pad addGestureRecognizer:tap];
}

- (BOOL)canBecomeFirstResponder {
  return YES;
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  ShowOrUpdateCursor();
  FocusWebContentOnExternalWindow();
  // If the non-interactive external scene cannot be the key window,
  // keep first responder here and forward hardware key presses.
  if (!g_external_window.isKeyWindow) {
    [self becomeFirstResponder];
  }
}

- (void)handleMove:(UIPanGestureRecognizer*)gesture {
  ShowOrUpdateCursor();
  if (!g_external_window) {
    return;
  }
  CGPoint translation = [gesture translationInView:gesture.view];
  [gesture setTranslation:CGPointZero inView:gesture.view];
  g_cursor_point.x += translation.x;
  g_cursor_point.y += translation.y;
  ShowOrUpdateCursor();
  NSInteger button = g_cursor_button_down ? 1 : 0;
  InjectMouseToHostedChrome(0, button);
}

- (void)handleTap:(UITapGestureRecognizer*)gesture {
  if (gesture.state != UIGestureRecognizerStateRecognized) {
    return;
  }
  ShowOrUpdateCursor();
  InjectMouseToHostedChrome(1, 1);
  InjectMouseToHostedChrome(2, 1);
}

- (void)handleScroll:(UIPanGestureRecognizer*)gesture {
  ShowOrUpdateCursor();
  CGPoint translation = [gesture translationInView:gesture.view];
  [gesture setTranslation:CGPointZero inView:gesture.view];
  // Finger down (positive UIKit y) scrolls the page down (Chrome
  // wheel deltas are positive up).
  CGPoint delta = CGPointMake(translation.x, -translation.y);
  if (gesture.state == UIGestureRecognizerStateBegan) {
    _scroll_phase = 0;
    InjectWheelToHostedChrome(delta, 0);
    _scroll_phase = 1;
  } else if (gesture.state == UIGestureRecognizerStateChanged) {
    InjectWheelToHostedChrome(delta, 1);
  } else if (gesture.state == UIGestureRecognizerStateEnded ||
             gesture.state == UIGestureRecognizerStateCancelled) {
    InjectWheelToHostedChrome(CGPointZero, 2);
    _scroll_phase = -1;
  }
}

- (void)pressesBegan:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event {
  FocusWebContentOnExternalWindow();
  UIView* widget = HostedRenderWidget();
  if (widget && widget != self.view &&
      [widget respondsToSelector:@selector(pressesBegan:withEvent:)]) {
    [widget pressesBegan:presses withEvent:event];
    return;
  }
  [super pressesBegan:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event {
  UIView* widget = HostedRenderWidget();
  if (widget && widget != self.view &&
      [widget respondsToSelector:@selector(pressesEnded:withEvent:)]) {
    [widget pressesEnded:presses withEvent:event];
    return;
  }
  [super pressesEnded:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress*>*)presses
               withEvent:(UIPressesEvent*)event {
  UIView* widget = HostedRenderWidget();
  if (widget && widget != self.view &&
      [widget respondsToSelector:@selector(pressesCancelled:withEvent:)]) {
    [widget pressesCancelled:presses withEvent:event];
    return;
  }
  [super pressesCancelled:presses withEvent:event];
}

@end

#pragma mark - Scene delegate

@implementation DeskBrowserExternalDisplaySceneDelegate

- (void)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                 options:(UISceneConnectionOptions*)connectionOptions {
  UIWindowScene* window_scene = (UIWindowScene*)scene;
  if (![window_scene isKindOfClass:[UIWindowScene class]]) {
    NSLog(@"deskbrowser-external: refusing non-window scene");
    return;
  }
  NSLog(@"deskbrowser-external: scene connecting role=%s bounds=%s",
        Pub(session.role),
        Pub(RectStr(window_scene.coordinateSpace.bounds)));

  UIWindow* window = [[UIWindow alloc] initWithWindowScene:window_scene];
  window.backgroundColor = [UIColor colorWithRed:0.13
                                           green:0.14
                                            blue:0.16
                                           alpha:1.0];
  self.window = window;
  if (g_legacy_mirror_window && g_external_window &&
      g_external_window != window) {
    g_external_window.hidden = YES;
    g_external_window.rootViewController = nil;
  }
  g_external_window = window;
  g_legacy_mirror_window = NO;
  SyncExternalWindowFrame(window_scene, window);
  window.hidden = NO;
  [window makeKeyAndVisible];
  PlaceChromeOnExternalDisplay();
}

- (void)windowScene:(UIWindowScene*)windowScene
    didUpdateEffectiveGeometry:
        (UIWindowSceneGeometry*)previousEffectiveGeometry {
  SyncExternalWindowFrame(windowScene, self.window);
}

- (void)sceneDidDisconnect:(UIScene*)scene {
  NSLog(@"deskbrowser-external: scene disconnected");
  RestoreChromeToPhoneIfNeeded();
  if (g_external_window == self.window) {
    g_external_window = nil;
    g_legacy_mirror_window = NO;
  }
  self.window = nil;
}

@end

#pragma mark - Public entry

void DeskBrowserExternalDisplayStart(void) {
  if (g_started && g_observing) {
    AttachTimerTick();
    return;
  }
  g_started = YES;
  // Touch the class so -dead_strip cannot drop the scene delegate.
  (void)[DeskBrowserExternalDisplaySceneDelegate class];
  (void)[DeskBrowserExternalControlSurfaceViewController class];

  if (!g_observing) {
    g_observing = YES;
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* notification) {
                      AttachTimerTick();
                    }];
    [center addObserverForName:UIScreenDidConnectNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* notification) {
                      NSLog(@"deskbrowser-external: UIScreen connected %@",
                            notification.object);
                      AttachTimerTick();
                    }];
    [center addObserverForName:UISceneWillConnectNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification* notification) {
                      UIScene* scene = (UIScene*)notification.object;
                      NSLog(@"deskbrowser-external: UIScene will connect %@ role=%@",
                            ClassName(scene),
                            ([scene isKindOfClass:[UIWindowScene class]]
                                 ? ((UIWindowScene*)scene).session.role
                                 : @"?"));
                      AttachTimerTick();
                    }];
  }

  if (!g_attach_timer) {
    g_attach_timer = [NSTimer
        scheduledTimerWithTimeInterval:0.25
                               repeats:YES
                                 block:^(NSTimer* timer) {
                                   AttachTimerTick();
                                 }];
  }
  AttachTimerTick();
  NSLog(@"deskbrowser-external: start (screens=%lu scenes=%lu)",
        (unsigned long)UIScreen.screens.count,
        (unsigned long)UIApplication.sharedApplication.connectedScenes.count);
}

UISceneConfiguration* DeskBrowserExternalDisplayConfigurationIfNeeded(
    UISceneSession* session) {
  if (!session) {
    return nil;
  }
  UISceneSessionRole role = session.role;
  if (RoleEquals(role, UIWindowSceneSessionRoleExternalDisplayNonInteractive) ||
      RoleEquals(role, UIWindowSceneSessionRoleExternalDisplay)) {
    NSLog(@"deskbrowser-external: configuration for connecting role=%@", role);
    UISceneConfiguration* config = [[UISceneConfiguration alloc]
        initWithName:@"DeskBrowser External Display"
        sessionRole:UIWindowSceneSessionRoleExternalDisplayNonInteractive];
    config.delegateClass = [DeskBrowserExternalDisplaySceneDelegate class];
    config.sceneClass = [UIWindowScene class];
    return config;
  }
  return nil;
}
