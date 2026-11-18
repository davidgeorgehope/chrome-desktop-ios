// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <UIKit/UIKit.h>

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
#include "ui/views/background.h"
#include "ui/views/controls/label.h"
#include "ui/views/layout/fill_layout.h"
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

class MilestoneView : public views::View {
 public:
  MilestoneView() {
    SetLayoutManager(std::make_unique<views::FillLayout>());
    SetBackground(views::CreateSolidBackground(SkColorSetRGB(0xC8, 0x1D, 0x25)));
    auto* label = AddChildView(std::make_unique<views::Label>(u"DeskBrowser Views M1"));
    label->SetAutoColorReadabilityEnabled(false);
    label->SetEnabledColor(SK_ColorWHITE);
    label->SetBackgroundColor(SkColorSetRGB(0xC8, 0x1D, 0x25));
    label->SetFontList(label->font_list().DeriveWithSizeDelta(16));
    label->SetHorizontalAlignment(gfx::ALIGN_CENTER);
  }
};

struct HostState {
  std::unique_ptr<ui::AXPlatformForTest> ax_platform;
  std::unique_ptr<display::ScopedNativeScreen> screen;
  std::unique_ptr<views::LayoutProvider> layout_provider;
  std::unique_ptr<ui::TestContextFactories> context_factories;
  std::unique_ptr<HostViewsDelegate> views_delegate;
  std::unique_ptr<views::Widget> widget;
};

HostState* g_host = nullptr;

void StartViewsWidget() {
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
  delegate->SetTitle(u"DeskBrowser Views M1");
  delegate->SetCanMaximize(false);
  delegate->SetCanMinimize(false);
  delegate->SetCanResize(true);
  delegate->SetContentsView(std::make_unique<MilestoneView>());
  views::Widget::InitParams params(views::Widget::InitParams::CLIENT_OWNS_WIDGET,
                                   views::Widget::InitParams::TYPE_WINDOW_FRAMELESS);
  params.delegate = delegate.release();
  params.bounds = gfx::Rect(16, 96, 370, 260);
  params.name = "DeskBrowserViewsM1";
  g_host->widget = std::make_unique<views::Widget>();
  g_host->widget->Init(std::move(params));
  g_host->widget->Show();
}

}  // namespace

@interface ViewsExamplesIOSSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation ViewsExamplesIOSSceneDelegate
- (void)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                 options:(UISceneConnectionOptions*)connectionOptions {
  auto* window_scene = (UIWindowScene*)scene;
  if (!self.window) {
    self.window = [[UIWindow alloc] initWithWindowScene:window_scene];
    self.window.rootViewController = [[UIViewController alloc] init];
    self.window.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1];
    [self.window makeKeyAndVisible];
  }
  StartViewsWidget();
}
@end

@interface ViewsExamplesIOSAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation ViewsExamplesIOSAppDelegate
- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  return YES;
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

  base::SingleThreadTaskExecutor executor(base::MessagePumpType::UI);

  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil,
                             NSStringFromClass([ViewsExamplesIOSAppDelegate class]));
  }
}
