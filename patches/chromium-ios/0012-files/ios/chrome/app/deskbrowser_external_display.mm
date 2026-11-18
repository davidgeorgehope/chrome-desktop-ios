// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/chrome/app/deskbrowser_external_display.h"

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

NSString* ClassName(id object) {
  return object ? NSStringFromClass([object class]) : @"nil";
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

UIWindow* PrimaryApplicationWindow(void) {
  UIWindow* fallback = nil;
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    UIWindowScene* window_scene = (UIWindowScene*)scene;
    if (![window_scene isKindOfClass:[UIWindowScene class]]) {
      continue;
    }
    if (window_scene.session.role != UIWindowSceneSessionRoleApplication) {
      continue;
    }
    for (UIWindow* window in window_scene.windows) {
      if (window == g_external_window) {
        continue;
      }
      if (window.isKeyWindow) {
        return window;
      }
      if (!fallback) {
        fallback = window;
      }
    }
  }
  return fallback;
}

void ForceRegularSizeClass(UIWindow* window);
void ClearSizeClassOverrides(UIViewController* vc);

void PreferLargestScreenMode(UIScreen* screen) {
  if (!screen) {
    return;
  }
  static __weak UIScreen* last_logged_screen = nil;
  static CGSize last_attempted_mode = {0, 0};
  static BOOL last_attempt_failed = NO;

  UIScreenMode* best = screen.currentMode;
  CGFloat best_area = best ? (best.size.width * best.size.height) : 0;
  NSMutableArray<NSString*>* modes = [NSMutableArray array];
  for (UIScreenMode* mode in screen.availableModes) {
    [modes addObject:NSStringFromCGSize(mode.size)];
    CGFloat area = mode.size.width * mode.size.height;
    if (area > best_area) {
      best = mode;
      best_area = area;
    }
  }
  if (last_logged_screen != screen) {
    NSLog(@"deskbrowser-external: screen bounds=%@ native=%@ scale=%.2f "
          @"currentMode=%@ available=[%@]",
          NSStringFromCGRect(screen.bounds),
          NSStringFromCGRect(screen.nativeBounds),
          screen.scale,
          screen.currentMode ? NSStringFromCGSize(screen.currentMode.size)
                             : @"nil",
          [modes componentsJoinedByString:@", "]);
    last_logged_screen = screen;
  }
  if (!best || best == screen.currentMode) {
    return;
  }
  if (last_attempt_failed &&
      CGSizeEqualToSize(last_attempted_mode, best.size)) {
    return;
  }
  last_attempted_mode = best.size;
  NSLog(@"deskbrowser-external: switching screen mode to %@",
        NSStringFromCGSize(best.size));
  screen.currentMode = best;
  last_attempt_failed =
      !screen.currentMode ||
      !CGSizeEqualToSize(screen.currentMode.size, best.size);
  if (last_attempt_failed) {
    NSLog(@"deskbrowser-external: system ignored mode switch; still %@",
          screen.currentMode ? NSStringFromCGSize(screen.currentMode.size)
                             : @"nil");
  }
}

void SyncExternalWindowFrame(UIWindowScene* window_scene, UIWindow* window) {
  if (!window_scene || !window) {
    return;
  }
  PreferLargestScreenMode(window_scene.screen);
  CGRect bounds = window_scene.coordinateSpace.bounds;
  if (CGRectIsEmpty(bounds) || bounds.size.width < 2 || bounds.size.height < 2) {
    bounds = window_scene.screen.bounds;
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


void RestoreChromeToPhoneIfNeeded(void);

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

  NSLog(@"deskbrowser-external: moving %@ onto the external display (%@)",
        ClassName(phone_root), NSStringFromCGSize(g_external_window.bounds.size));

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
  [g_external_window makeKeyAndVisible];
  // Keep the phone window visible as the control surface; the
  // external window is key so hardware keyboard focuses the desktop
  // chrome. Mouse clicks on a non-interactive external scene may not
  // be delivered; the phone remains the pointer surface.
  [phone setHidden:NO];
}

void RestoreChromeToPhoneIfNeeded(void) {
  if (!g_hosted_chrome_vc) {
    return;
  }
  UIWindow* phone = g_phone_window ?: PrimaryApplicationWindow();
  NSLog(@"deskbrowser-external: restoring %@ to the phone",
        ClassName(g_hosted_chrome_vc));
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

UIViewController* PresenterViewController(void) {
  UIWindow* phone = PrimaryApplicationWindow();
  UIViewController* root = phone.rootViewController;
  if (!root) {
    return nil;
  }
  while (root.presentedViewController) {
    root = root.presentedViewController;
  }
  return root;
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
                @"presenter=%@",
                registration.isAvailable, registration.isEnabled,
                ClassName(previous));
        }
        return;
      }
      NSLog(@"deskbrowser-external: presenter changed (%@ -> %@); "
            @"re-registering accessory",
            ClassName(previous), ClassName(presenter));
      UnregisterAccessory();
    }

    if (!presenter || !presenter.viewIfLoaded.window) {
      return;
    }

    UISceneAccessory* accessory = [UISceneAccessory
        externalNonInteractiveSceneAccessoryWithConfiguration:
            ExternalSceneConfiguration()];
    UISceneAccessoryRegistration* registration =
        [presenter registerSceneAccessory:accessory];
    if (!registration) {
      NSLog(@"deskbrowser-external: registerSceneAccessory returned nil on %@",
            ClassName(presenter));
      return;
    }
    registration.enabled = YES;
    g_accessory_registration = registration;
    g_accessory_presenter = presenter;
    NSLog(@"deskbrowser-external: registered iOS 27 scene accessory on %@ "
          @"available=%d",
          ClassName(presenter), registration.isAvailable);
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
    if (role == UIWindowSceneSessionRoleExternalDisplayNonInteractive ||
        role == UIWindowSceneSessionRoleExternalDisplay) {
      return YES;
    }
  }
  return g_legacy_mirror_window && !g_external_window.hidden;
}

// When iOS is mirroring the phone to a connected display, Apple's
// UIScreen.mirroredScreen docs say: "Moving a UIWindow to this screen
// will disable mirroring." iOS 27 may keep mirroring if the scene
// accessory never takes over; this fallback claims the display.
UIScreen* MirroredOrExternalScreen(void) {
  UIScreen* main = UIScreen.mainScreen;
  if (main.mirroredScreen && !CGRectIsEmpty(main.mirroredScreen.bounds)) {
    return main.mirroredScreen;
  }
  for (UIScreen* screen in UIScreen.screens) {
    if (screen == main) {
      continue;
    }
    if (CGRectIsEmpty(screen.bounds)) {
      continue;
    }
    return screen;
  }
  return nil;
}

void AttachLegacyWindowIfMirroring(void) {
  if (HasExternalSceneWindow() && !g_legacy_mirror_window) {
    return;
  }
  UIScreen* ext = MirroredOrExternalScreen();
  if (!ext) {
    return;
  }
  if (g_legacy_mirror_window && g_external_window) {
    if (!CGRectEqualToRect(g_external_window.frame, ext.bounds)) {
      g_external_window.frame = ext.bounds;
    }
    ForceRegularSizeClass(g_external_window);
    PlaceChromeOnExternalDisplay();
    return;
  }

  NSLog(@"deskbrowser-external: taking over mirrored/external UIScreen %@ "
        @"bounds=%@ (scene accessory did not create a session)",
        ext, NSStringFromCGRect(ext.bounds));

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  UIWindow* window = [[UIWindow alloc] initWithFrame:ext.bounds];
  window.screen = ext;
#pragma clang diagnostic pop
  window.backgroundColor = [UIColor colorWithRed:0.13
                                           green:0.14
                                            blue:0.16
                                           alpha:1.0];
  g_external_window = window;
  g_legacy_mirror_window = YES;
  ForceRegularSizeClass(window);
  window.hidden = NO;
  [window makeKeyAndVisible];
  PlaceChromeOnExternalDisplay();
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
                           stringWithFormat:@"bounds=%@ mirrored=%@ scale=%.1f",
                                            NSStringFromCGRect(screen.bounds),
                                            screen.mirroredScreen ? @"Y" : @"N",
                                            screen.scale]];
  }
  NSMutableArray<NSString*>* roles = [NSMutableArray array];
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
      [roles addObject:((UIWindowScene*)scene).session.role];
    }
  }
  NSLog(@"deskbrowser-external: screens=[%@] mirrored=%@ scenes=[%@] "
        @"legacy=%d extWin=%@",
        [screens componentsJoinedByString:@"; "],
        UIScreen.mainScreen.mirroredScreen ? @"Y" : @"N",
        [roles componentsJoinedByString:@","],
        g_legacy_mirror_window, g_external_window ? @"Y" : @"N");
}

void AttachTimerTick(void) {
  LogDisplayStateOnceInAWhile();
  RegisterAccessoryIfPossible();
  if (g_external_window && !g_legacy_mirror_window) {
    if (g_external_window.windowScene) {
      SyncExternalWindowFrame(g_external_window.windowScene,
                              g_external_window);
    }
    PlaceChromeOnExternalDisplay();
    return;
  }
  // Prefer a real external scene when it arrives; otherwise take over
  // the mirrored UIScreen so the monitor is not left as a phone mirror.
  if (!HasExternalSceneWindow()) {
    AttachLegacyWindowIfMirroring();
  } else {
    PlaceChromeOnExternalDisplay();
  }
}

}  // namespace

#pragma mark - Control surface

@interface DeskBrowserExternalControlSurfaceViewController : UIViewController
@end

@implementation DeskBrowserExternalControlSurfaceViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor colorWithRed:0.13
                                              green:0.14
                                               blue:0.16
                                              alpha:1.0];

  UILabel* title = [[UILabel alloc] init];
  title.text = @"Chrome is on your monitor";
  title.textColor = [UIColor whiteColor];
  title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
  title.textAlignment = NSTextAlignmentCenter;
  title.numberOfLines = 0;
  title.translatesAutoresizingMaskIntoConstraints = NO;

  UILabel* body = [[UILabel alloc] init];
  body.text = @"The desktop Chrome window is on the connected display: tab "
              @"strip, toolbar, and a full-width page.\n\nUse a keyboard "
              @"attached to this iPhone to type in that window. Mouse "
              @"clicks on the monitor may not be delivered — iOS presents "
              @"this as a non-interactive external display, so this screen "
              @"is the control surface.\n\nUnplug the monitor to bring "
              @"Chrome back here.";
  body.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
  body.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
  body.textAlignment = NSTextAlignmentCenter;
  body.numberOfLines = 0;
  body.translatesAutoresizingMaskIntoConstraints = NO;

  UIStackView* stack =
      [[UIStackView alloc] initWithArrangedSubviews:@[ title, body ]];
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 16;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                        constant:28],
    [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                         constant:-28],
    [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
  ]];
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
  NSLog(@"deskbrowser-external: scene connecting role=%@ screen=%@ bounds=%@",
        session.role, window_scene.screen,
        NSStringFromCGRect(window_scene.coordinateSpace.bounds));

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
  if (role == UIWindowSceneSessionRoleExternalDisplayNonInteractive ||
      role == UIWindowSceneSessionRoleExternalDisplay) {
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
