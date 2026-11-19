// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Host app for the real //chrome desktop BrowserView on iOS (desktop Views,
// Mac-style Views without Aura). Runs Chrome's own ContentMainDelegate
// in-process, the same way content_shell does on iOS. Browser windows are
// Views widgets; NativeWidgetIOS places them on the external display.

#import <UIKit/UIKit.h>

#include <memory>

#include "base/at_exit.h"

#include "base/time/time.h"
#include "chrome/app/chrome_main_delegate.h"
#include "chrome/app/startup_timestamps.h"
#include "content/public/app/content_main.h"
#include "content/public/app/content_main_runner.h"

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
@end

@implementation ChromeViewsIOSSceneDelegate
- (void)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                 options:(UISceneConnectionOptions*)connectionOptions {
  UIWindowScene* windowScene = (UIWindowScene*)scene;
  self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
  UIViewController* controller = [[UIViewController alloc] init];
  controller.view.backgroundColor = UIColor.blackColor;
  self.window.rootViewController = controller;
  [self.window makeKeyAndVisible];
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

int main(int argc, char* argv[]) {
  base::AtExitManager at_exit;
  g_exe_entry = base::TimeTicks::Now();
  g_argc = argc;
  g_argv = const_cast<const char**>(argv);
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil,
                             NSStringFromClass([ChromeViewsIOSAppDelegate class]));
  }
}
