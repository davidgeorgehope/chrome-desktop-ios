// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <UIKit/UIKit.h>

#include <algorithm>
#include <memory>

#include "base/apple/foundation_util.h"
#include "base/at_exit.h"
#include "base/files/file_util.h"
#include "base/command_line.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/i18n/icu_util.h"
#include "base/memory/raw_ptr.h"
#include "base/message_loop/message_pump_type.h"
#include "base/path_service.h"
#include "base/task/single_thread_task_executor.h"
#include "base/task/single_thread_task_runner.h"
#include "base/task/thread_pool/thread_pool_instance.h"
#include "mojo/core/embedder/embedder.h"
#include "ui/accessibility/platform/ax_platform_for_test.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/base/ui_base_paths.h"
#include "ui/color/color_mixers.h"
#include "ui/color/color_provider_manager.h"
#include "ui/compositor/test/test_context_factories.h"
#include "ui/display/screen.h"
#include "ui/gfx/font_util.h"
#include "ui/gl/gl_utils.h"
#include "ui/gl/init/gl_factory.h"
#include "ui/gfx/geometry/size.h"
#include "ui/views/background.h"
#include "ui/views/examples/ios/desktop_browser_chrome_view.h"
#include "ui/views/layout/layout_provider.h"
#include "ui/views/view.h"
#include "ui/views/views_delegate.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_delegate.h"

namespace {

class HostViewsDelegate : public views::ViewsDelegate {
 public:
  explicit HostViewsDelegate(ui::ContextFactory* factory) : factory_(factory) {}
  ui::ContextFactory* GetContextFactory() override { return factory_; }

 private:
  raw_ptr<ui::ContextFactory> factory_;
};

struct HostState {
  std::unique_ptr<ui::AXPlatformForTest> ax_platform;
  std::unique_ptr<display::ScopedNativeScreen> screen;
  std::unique_ptr<views::LayoutProvider> layout_provider;
  std::unique_ptr<ui::TestContextFactories> context_factories;
  std::unique_ptr<HostViewsDelegate> views_delegate;
  std::unique_ptr<views::Widget> widget;
  raw_ptr<DesktopBrowserChromeView> chrome = nullptr;
};

HostState* g_host = nullptr;
base::SingleThreadTaskExecutor* g_ui_executor = nullptr;

// On iOS the UI MessagePump must be attached while UIApplication's
// CFRunLoop is already running (MessagePumpUIApplication::OnAttach assumes
// nesting_level == 1). Creating SingleThreadTaskExecutor in main() before
// UIApplicationMain leaves compositor tasks un-pumped and the widget blank.
void EnsureChromeUIExecutor() {
  if (g_ui_executor) {
    return;
  }
  g_ui_executor = new base::SingleThreadTaskExecutor(base::MessagePumpType::UI);
  NSLog(@"[DeskBrowser] attached UI MessagePump to the running CFRunLoop");
}

void StartViewsWidget() {
  EnsureChromeUIExecutor();
  if (g_host && g_host->widget) {
    return;
  }
  if (!g_host) {
    g_host = new HostState();
  }
  if (!g_host->layout_provider) {
    g_host->ax_platform = std::make_unique<ui::AXPlatformForTest>();
    g_host->screen = std::make_unique<display::ScopedNativeScreen>();
    g_host->layout_provider = std::make_unique<views::LayoutProvider>();
    ui::ColorProviderManager::Get().AppendColorProviderInitializer(
        base::BindRepeating(&ui::AddColorMixers));
    g_host->context_factories =
        std::make_unique<ui::TestContextFactories>(/*under_test=*/false,
                                                   /*output_to_window=*/true);
    g_host->views_delegate = std::make_unique<HostViewsDelegate>(
        g_host->context_factories->GetContextFactory());
  }

  auto delegate = std::make_unique<views::WidgetDelegate>();
  delegate->SetTitle(u"DeskBrowser Views M2");
  delegate->SetCanMaximize(false);
  delegate->SetCanMinimize(false);
  delegate->SetCanResize(true);
  auto chrome = std::make_unique<DesktopBrowserChromeView>();
  g_host->chrome = chrome.get();
  delegate->SetContentsView(std::move(chrome));
  views::Widget::InitParams params(views::Widget::InitParams::CLIENT_OWNS_WIDGET,
                                   views::Widget::InitParams::TYPE_WINDOW_FRAMELESS);
  params.delegate = delegate.release();
  params.bounds = gfx::Rect(16, 96, 370, 260);
  params.name = "DeskBrowserViewsM2";
  g_host->widget = std::make_unique<views::Widget>();
  g_host->widget->Init(std::move(params));
  g_host->widget->Show();
}


void DispatchPhoneTrackpad(CGPoint fraction, bool click) {
  if (!g_host || !g_host->chrome || !g_host->widget || !g_host->widget->GetRootView()) {
    return;
  }
  const gfx::Size size = g_host->widget->GetRootView()->size();
  const int x = std::clamp(static_cast<int>(fraction.x * size.width()), 0,
                           std::max(0, size.width() - 1));
  const int y = std::clamp(static_cast<int>(fraction.y * size.height()), 0,
                           std::max(0, size.height() - 1));
  g_host->chrome->OnTrackpadMove(gfx::Point(x, y), click);
}

}  // namespace

@interface ViewsExamplesIOSSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

static id g_views_accessory_registration = nil;
static UIViewController* g_views_accessory_presenter = nil;

BOOL ViewsRoleEquals(NSString* role, UISceneSessionRole expected) {
  return [role isEqualToString:expected];
}

BOOL ViewsIsExternalScene(UIWindowScene* scene) {
  if (!scene) {
    return NO;
  }
  NSString* role = scene.session.role;
  if (ViewsRoleEquals(role, UIWindowSceneSessionRoleExternalDisplayNonInteractive)) {
    return YES;
  }
#ifdef UIWindowSceneSessionRoleExternalDisplay
  if (ViewsRoleEquals(role, UIWindowSceneSessionRoleExternalDisplay)) {
    return YES;
  }
#endif
  return NO;
}

UIWindowScene* ViewsPreferredWindowScene() {
  UIWindowScene* external = nil;
  UIWindowScene* large = nil;
  UIWindowScene* app = nil;
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
      continue;
    }
    UIWindowScene* window_scene = (UIWindowScene*)scene;
    NSString* role = window_scene.session.role;
    if (ViewsIsExternalScene(window_scene)) {
      external = window_scene;
    }
    if (ViewsRoleEquals(role, UIWindowSceneSessionRoleApplication)) {
      app = window_scene;
    }
    CGSize size = window_scene.screen.bounds.size;
    if (size.width >= 1280 && size.height >= 720) {
      large = window_scene;
    }
  }
  return external ? external : (large ? large : app);
}

void PlaceWidgetOnScene(UIWindowScene* scene) {
  if (!g_host || !g_host->widget || !scene) {
    return;
  }
  UIWindow* window = g_host->widget->GetNativeWindow().Get();
  if (!window) {
    return;
  }
  if (window.windowScene != scene) {
    window.windowScene = scene;
  }
  CGRect bounds = scene.screen.bounds;
  g_host->widget->SetBounds(gfx::Rect(
      static_cast<int>(bounds.origin.x), static_cast<int>(bounds.origin.y),
      static_cast<int>(bounds.size.width), static_cast<int>(bounds.size.height)));
  window.hidden = NO;
  [window makeKeyAndVisible];
  if (auto* root = g_host->widget->GetRootView()) {
    NSLog(@"[DeskBrowser] place root_view=%dx%d", root->width(), root->height());
    root->SchedulePaint();
  }
  // SetBounds already scheduled a draw; paint again after layout settles.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   if (!g_host || !g_host->widget) {
                     return;
                   }
                   if (auto* root = g_host->widget->GetRootView()) {
                     root->SchedulePaint();
                   }
                   g_host->widget->SchedulePaintInRect(g_host->widget->GetRootView()->GetLocalBounds());
                 });
  NSLog(@"[DeskBrowser] placed widget on role=%s screen=%.0fx%.0f scale=%.1f "
        @"frame=%.0f,%.0f %.0fx%.0f hidden=%d key=%d",
        scene.session.role.UTF8String, bounds.size.width, bounds.size.height,
        scene.screen.scale, window.frame.origin.x, window.frame.origin.y,
        window.frame.size.width, window.frame.size.height, window.hidden,
        window.isKeyWindow);
}

void PlaceWidgetOnPreferredScene() {
  PlaceWidgetOnScene(ViewsPreferredWindowScene());
}

void RegisterViewsExternalAccessory(UIViewController* presenter) {
#if defined(__IPHONE_27_0)
  if (@available(iOS 27.0, *)) {
    if (!presenter || !presenter.view.window) {
      return;
    }
    if (g_views_accessory_registration &&
        g_views_accessory_presenter == presenter) {
      ((UISceneAccessoryRegistration*)g_views_accessory_registration).enabled =
          YES;
      return;
    }
    UISceneConfiguration* config = [[UISceneConfiguration alloc]
        initWithName:@"External Display"
        sessionRole:UIWindowSceneSessionRoleExternalDisplayNonInteractive];
    config.delegateClass = [ViewsExamplesIOSSceneDelegate class];
    config.sceneClass = [UIWindowScene class];
    UISceneAccessory* accessory = [UISceneAccessory
        externalNonInteractiveSceneAccessoryWithConfiguration:config];
    UISceneAccessoryRegistration* registration =
        [presenter registerSceneAccessory:accessory];
    if (!registration) {
      NSLog(@"[DeskBrowser] registerSceneAccessory returned nil");
      return;
    }
    registration.enabled = YES;
    g_views_accessory_registration = registration;
    g_views_accessory_presenter = presenter;
    NSLog(@"[DeskBrowser] registered iOS 27 external accessory available=%d",
          registration.isAvailable);
  }
#endif
}


@interface DeskBrowserPhoneTrackpadView : UIView
@property(nonatomic, strong) UIView* fingerDot;
@property(nonatomic, strong) UILabel* caption;
@property(nonatomic, assign) BOOL didMove;
@end

@implementation DeskBrowserPhoneTrackpadView
- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1];
    self.multipleTouchEnabled = NO;
    self.caption = [[UILabel alloc] init];
    self.caption.text = @"Trackpad\nDrag to move the pointer on the desktop display.\nTap to click.";
    self.caption.textColor = [UIColor colorWithWhite:0.82 alpha:1];
    self.caption.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    self.caption.numberOfLines = 0;
    self.caption.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.caption];
    self.fingerDot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 22, 22)];
    self.fingerDot.backgroundColor = [UIColor colorWithWhite:1 alpha:0.85];
    self.fingerDot.layer.cornerRadius = 11;
    self.fingerDot.hidden = YES;
    [self addSubview:self.fingerDot];
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat pad = 24;
  self.caption.frame = CGRectInset(self.bounds, pad, pad);
}

- (CGPoint)fractionForTouch:(UITouch*)touch {
  CGPoint p = [touch locationInView:self];
  CGSize s = self.bounds.size;
  CGFloat x = s.width > 0 ? p.x / s.width : 0;
  CGFloat y = s.height > 0 ? p.y / s.height : 0;
  x = MIN(MAX(x, 0), 1);
  y = MIN(MAX(y, 0), 1);
  return CGPointMake(x, y);
}

- (void)showDotAtTouch:(UITouch*)touch {
  CGPoint p = [touch locationInView:self];
  self.fingerDot.center = p;
  self.fingerDot.hidden = NO;
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  self.didMove = NO;
  UITouch* touch = [touches anyObject];
  [self showDotAtTouch:touch];
  DispatchPhoneTrackpad([self fractionForTouch:touch], false);
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  self.didMove = YES;
  UITouch* touch = [touches anyObject];
  [self showDotAtTouch:touch];
  DispatchPhoneTrackpad([self fractionForTouch:touch], false);
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  UITouch* touch = [touches anyObject];
  [self showDotAtTouch:touch];
  DispatchPhoneTrackpad([self fractionForTouch:touch], !self.didMove);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   self.fingerDot.hidden = YES;
                 });
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  self.fingerDot.hidden = YES;
}
@end

void InstallPhoneTrackpad(UIWindow* window) {
  if (!window || !window.rootViewController) {
    return;
  }
  UIView* host = window.rootViewController.view;
  for (UIView* child in host.subviews) {
    if ([child isKindOfClass:[DeskBrowserPhoneTrackpadView class]]) {
      return;
    }
  }
  DeskBrowserPhoneTrackpadView* pad =
      [[DeskBrowserPhoneTrackpadView alloc] initWithFrame:host.bounds];
  pad.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [host addSubview:pad];
  NSLog(@"[DeskBrowser] installed phone trackpad on application scene");
}

@implementation ViewsExamplesIOSSceneDelegate
- (void)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                 options:(UISceneConnectionOptions*)connectionOptions {
  auto* window_scene = (UIWindowScene*)scene;
  NSLog(@"[DeskBrowser] scene willConnect role=%s screen=%.0fx%.0f scale=%.1f",
        window_scene.session.role.UTF8String,
        window_scene.screen.bounds.size.width,
        window_scene.screen.bounds.size.height, window_scene.screen.scale);
  if (ViewsIsExternalScene(window_scene)) {
    StartViewsWidget();
    PlaceWidgetOnScene(window_scene);
    return;
  }
  if (!self.window) {
    self.window = [[UIWindow alloc] initWithWindowScene:window_scene];
    self.window.rootViewController = [[UIViewController alloc] init];
    self.window.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1];
    [self.window makeKeyAndVisible];
  }
  InstallPhoneTrackpad(self.window);
  RegisterViewsExternalAccessory(self.window.rootViewController);
  StartViewsWidget();
  // TVOut / the official scene may connect just after the app scene.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   RegisterViewsExternalAccessory(self.window.rootViewController);
                   PlaceWidgetOnPreferredScene();
                 });
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   RegisterViewsExternalAccessory(self.window.rootViewController);
                   PlaceWidgetOnPreferredScene();
                 });
}
@end

@interface ViewsExamplesIOSAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation ViewsExamplesIOSAppDelegate
- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  EnsureChromeUIExecutor();
  return YES;
}

- (UISceneConfiguration*)application:(UIApplication*)application
    configurationForConnectingSceneSession:(UISceneSession*)connectingSceneSession
                                   options:(UISceneConnectionOptions*)options {
  if (ViewsRoleEquals(connectingSceneSession.role,
                      UIWindowSceneSessionRoleExternalDisplayNonInteractive)) {
    UISceneConfiguration* config = [[UISceneConfiguration alloc]
        initWithName:@"External Display"
        sessionRole:connectingSceneSession.role];
    config.delegateClass = [ViewsExamplesIOSSceneDelegate class];
    config.sceneClass = [UIWindowScene class];
    return config;
  }
  UISceneConfiguration* config = [[UISceneConfiguration alloc]
      initWithName:@"Default Configuration"
      sessionRole:connectingSceneSession.role];
  config.delegateClass = [ViewsExamplesIOSSceneDelegate class];
  config.sceneClass = [UIWindowScene class];
  return config;
}
@end

int main(int argc, char* argv[]) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  base::ThreadPoolInstance::CreateAndStartWithDefaultParams("ViewsExamplesIOS");
  mojo::core::Init();
  CHECK(base::i18n::InitializeICU());
  gfx::InitializeFonts();
  ui::RegisterPathProvider();
  gl::init::InitializeGLOneOff(/*gpu_preference=*/gl::GpuPreference::kDefault);

  base::FilePath pak_path;
  if (NSString* pak = [[NSBundle mainBundle] pathForResource:@"ui_test"
                                                      ofType:@"pak"]) {
    pak_path = base::apple::NSStringToFilePath(pak);
  } else if (!base::PathService::Get(ui::UI_TEST_PAK, &pak_path) ||
             !base::PathExists(pak_path)) {
    pak_path = base::apple::NSStringToFilePath(
        [[NSBundle mainBundle] bundlePath]).AppendASCII("ui_test.pak");
  }
  CHECK(base::PathExists(pak_path)) << pak_path;
  ui::ResourceBundle::InitSharedInstanceWithPakPath(pak_path);

  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil,
                             NSStringFromClass([ViewsExamplesIOSAppDelegate class]));
  }
}
