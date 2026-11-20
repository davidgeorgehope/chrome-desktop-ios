// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Host app for the real //chrome desktop BrowserView on iOS (desktop Views,
// Mac-style Views without Aura). Runs Chrome's own ContentMainDelegate
// in-process, the same way content_shell does on iOS. Browser windows are
// Views widgets; NativeWidgetIOS places them on the external display.

#import <UIKit/UIKit.h>

#include <memory>
#include <string>
#include <vector>

#include "base/at_exit.h"
#include "base/compiler_specific.h"
#include "base/containers/span.h"
#include "base/no_destructor.h"

#include "base/time/time.h"
#include "chrome/app/chrome_main_delegate.h"
#include "chrome/app/startup_timestamps.h"
#import "chrome/browser/ui/views/ios/views_trackpad_ios.h"
#include "content/public/app/content_main.h"
#include "content/public/app/content_main_runner.h"
#include "ui/views/widget/native_widget_ios.h"

namespace {
int g_argc = 0;
const char** g_argv = nullptr;
base::TimeTicks g_exe_entry;
// Leaked on purpose: they live for the whole process, like content_shell.
content::ContentMainRunner* g_main_runner = nullptr;
ChromeMainDelegate* g_main_delegate = nullptr;
}  // namespace

// The phone scene is a plain surface (the trackpad role lives in the
// external-display presenter). Browser windows are not UIWindows here.
@interface ChromeViewsIOSSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow* window;
// iOS 27 only connects the external-display scene for an app that registers
// a UISceneAccessory; Info.plist alone mirrors the phone. Held for the
// lifetime of the phone scene (typed id so older SDKs still compile).
@property(nonatomic, strong) id accessoryRegistration;
@end

@implementation ChromeViewsIOSSceneDelegate
- (void)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                 options:(UISceneConnectionOptions*)connectionOptions {
  UIWindowScene* windowScene = (UIWindowScene*)scene;
  BOOL external = ![session.role
      isEqualToString:UIWindowSceneSessionRoleApplication];
  NSLog(@"[DeskBrowser] scene willConnect role=%@", session.role);
  self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
  UIViewController* controller = [[UIViewController alloc] init];
  controller.view.backgroundColor = UIColor.blackColor;
  self.window.rootViewController = controller;
  if (external) {
    // Browser widgets (NativeWidgetIOS) move onto this scene and draw above.
    self.window.windowLevel = UIWindowLevelNormal - 1;
    self.window.hidden = NO;
    return;
  }
  [self.window makeKeyAndVisible];
  // The phone becomes a trackpad while an external display is connected.
  ChromeViewsIOSTrackpadView* trackpad =
      [[ChromeViewsIOSTrackpadView alloc] initWithFrame:controller.view.bounds];
  trackpad.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [controller.view addSubview:trackpad];
  [self registerExternalDisplayAccessoryOn:controller];
}

- (void)windowScene:(UIWindowScene*)windowScene
    didUpdateCoordinateSpace:(id<UICoordinateSpace>)previousCoordinateSpace
        interfaceOrientation:(UIInterfaceOrientation)previousInterfaceOrientation
             traitCollection:(UITraitCollection*)previousTraitCollection {
  if ([windowScene.session.role
          isEqualToString:UIWindowSceneSessionRoleApplication]) {
    return;
  }
  NSLog(@"[DeskBrowser] external scene geometry %@",
        NSStringFromCGRect(windowScene.screen.bounds));
  views::NativeWidgetIOS::ExternalSceneGeometryChanged();
}

- (void)registerExternalDisplayAccessoryOn:(UIViewController*)presenter {
#if defined(__IPHONE_27_0)
  if (@available(iOS 27.0, *)) {
    // Register on a view controller that stays on the phone scene; moving the
    // presenter to the external window makes iOS disconnect the scene.
    UISceneConfiguration* config = [[UISceneConfiguration alloc]
        initWithName:@"External Display"
         sessionRole:UIWindowSceneSessionRoleExternalDisplayNonInteractive];
    config.delegateClass = ChromeViewsIOSSceneDelegate.class;
    config.sceneClass = UIWindowScene.class;
    UISceneAccessory* accessory = [UISceneAccessory
        externalNonInteractiveSceneAccessoryWithConfiguration:config];
    UISceneAccessoryRegistration* registration =
        [presenter registerSceneAccessory:accessory];
    registration.enabled = YES;
    self.accessoryRegistration = registration;
    NSLog(@"[DeskBrowser] external accessory registered=%d available=%d",
          registration != nil, registration.isAvailable);
  }
#endif
}
@end

@interface ChromeViewsIOSAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation ChromeViewsIOSAppDelegate
- (UISceneConfiguration*)application:(UIApplication*)application
    configurationForConnectingSceneSession:
        (UISceneSession*)connectingSceneSession
                                   options:(UISceneConnectionOptions*)options {
  UISceneConfiguration* configuration =
      [[UISceneConfiguration alloc] initWithName:nil
                                     sessionRole:connectingSceneSession.role];
  configuration.delegateClass = ChromeViewsIOSSceneDelegate.class;
  return configuration;
}

- (BOOL)application:(UIApplication*)application
    willFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  // The desktop window belongs on the monitor only; the phone shows the
  // trackpad (or a "connect a monitor" hint).
  views::NativeWidgetIOS::SetRequireExternalDisplay(true);
  StartupTimestamps timestamps;
  timestamps.exe_entry_point_ticks = g_exe_entry;
  g_main_delegate = new ChromeMainDelegate(timestamps);
  content::ContentMainParams params(g_main_delegate);
  params.argc = g_argc;
  params.argv = g_argv;
  g_main_runner = content::ContentMainRunner::Create().release();
  content::RunContentProcess(std::move(params), g_main_runner);
  return YES;
}

- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  return YES;
}
@end

// This bundle ships no BrowserEngineKit child-process extensions, so the
// renderer and GPU must run in the browser process (as on the deskbrowser
// device build; see content_main.cc). Defaults are added unless the caller
// already passed them.
void BuildDefaultArgv(int argc, char* argv[]) {
  static base::NoDestructor<std::vector<std::string>> args;
  static base::NoDestructor<std::vector<const char*>> ptrs;
  bool has_single = false, has_gpu = false, has_disable = false,
       has_js_flags = false;
  // SAFETY: argv has argc entries, as passed to main().
  base::span<char*> raw_args =
      UNSAFE_BUFFERS(base::span(argv, static_cast<size_t>(argc)));
  for (const char* raw_arg : raw_args) {
    std::string arg(raw_arg);
    has_single |= arg == "--single-process";
    has_gpu |= arg == "--in-process-gpu";
    has_disable |= arg.rfind("--disable-features=", 0) == 0;
    has_js_flags |= arg.rfind("--js-flags=", 0) == 0;
    args->push_back(arg);
  }
  if (!has_single) {
    args->push_back("--single-process");
  }
  if (!has_gpu) {
    args->push_back("--in-process-gpu");
  }
  if (!has_disable) {
    // Must be off in single-process (see run-chrome-ios-blink-sim.sh).
    args->push_back(
        "--disable-features=NetTaskScheduler,NetworkServiceTaskScheduler");
  }
  if (!has_js_flags) {
    // No JIT entitlement here: V8 must not remap builtins into a JIT code
    // range (BUS_ADRALN in CodeRange::RemapEmbeddedBuiltins otherwise).
    args->push_back("--js-flags=--jitless");
  }
  for (const std::string& arg : *args) {
    ptrs->push_back(arg.c_str());
  }
  g_argc = static_cast<int>(ptrs->size());
  g_argv = ptrs->data();
}

int main(int argc, char* argv[]) {
  base::AtExitManager at_exit;
  g_exe_entry = base::TimeTicks::Now();
  BuildDefaultArgv(argc, argv);
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil,
                             NSStringFromClass([ChromeViewsIOSAppDelegate class]));
  }
}
