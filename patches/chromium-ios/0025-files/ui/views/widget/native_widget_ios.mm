// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ui/views/widget/native_widget_ios.h"

#import <UIKit/UIKit.h>

#include <map>

#include "base/check.h"
#include "base/memory/ptr_util.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/notimplemented.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "ui/accelerated_widget_mac/ca_layer_frame_sink.h"
#include "ui/accelerated_widget_mac/display_ca_layer_tree.h"
#include "ui/base/ime/input_method.h"
#include "ui/base/ime/init/input_method_factory.h"
#include "ui/compositor/compositor.h"
#include "ui/compositor/layer.h"
#include "ui/compositor/paint_context.h"
#include "ui/display/screen.h"
#include "ui/gfx/font_list.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size_conversions.h"
#include "ui/views/view.h"
#include "ui/views/views_delegate.h"
#include "ui/views/widget/tooltip_manager.h"
#include "ui/views/widget/widget_delegate.h"
#include "ui/base/dragdrop/os_exchange_data.h"

// Views-only UIView host. Do not subclass CALayerFrameSinkProvider:
// on non-tvOS that class is a BELayerHierarchyHostingView, which swallows
// a DisplayCALayerTree attached to its layer on the iOS Simulator.
@interface DeskBrowserViewsContentView : UIView
- (gfx::AcceleratedWidget)viewHandle;
- (ui::CALayerFrameSink*)frameSink;
- (ui::DisplayCALayerTree*)displayCALayerTree;
@end

@implementation DeskBrowserViewsContentView {
  std::unique_ptr<ui::DisplayCALayerTree> _tree;
  gfx::AcceleratedWidget _handle;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.opaque = YES;
    self.backgroundColor = [UIColor colorWithRed:0.13
                                           green:0.14
                                            blue:0.16
                                           alpha:1.0];
    self.clipsToBounds = YES;
    CGFloat scale = 1;
    if (self.window.screen) {
      scale = self.window.screen.scale;
    } else if (UIScreen.mainScreen) {
      scale = UIScreen.mainScreen.scale;
    }
    self.layer.contentsScale = scale;
    _tree = std::make_unique<ui::DisplayCALayerTree>(self.layer);
    _handle = ui::RegisterUnownedCALayerFrameSink(_tree.get());
    ui::RegisterUnownedHostCALayer(_handle, self.layer);
    NSLog(@"[DeskBrowser] content view init frame=%.1fx%.1f scale=%.1f "
          @"handle=%llu",
          self.frame.size.width, self.frame.size.height, scale,
          (unsigned long long)_handle);
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  for (CALayer* sub in self.layer.sublayers) {
    if (!CGRectEqualToRect(sub.frame, self.layer.bounds)) {
      sub.frame = self.layer.bounds;
    }
    if (sub.contentsScale != self.layer.contentsScale) {
      sub.contentsScale = self.layer.contentsScale;
    }
  }
  static NSInteger layouts = 0;
  if (layouts < 8) {
    layouts++;
    NSLog(@"[DeskBrowser] layout #%ld bounds=%.1fx%.1f scale=%.1f sublayers=%lu",
          (long)layouts, self.bounds.size.width, self.bounds.size.height,
          self.layer.contentsScale, (unsigned long)self.layer.sublayers.count);
  }
}

- (void)dealloc {
  if (_handle) {
    ui::UnregisterUnownedCALayerFrameSink(_handle);
    _handle = gfx::kNullAcceleratedWidget;
  }
}

- (gfx::AcceleratedWidget)viewHandle {
  return _handle;
}

- (ui::CALayerFrameSink*)frameSink {
  return _tree.get();
}

- (ui::DisplayCALayerTree*)displayCALayerTree {
  return _tree.get();
}
@end

namespace views {
namespace {

NativeWidgetIOS* g_capture_widget = nullptr;

std::map<UIWindow*, NativeWidgetIOS*>& WindowMap() {
  static base::NoDestructor<std::map<UIWindow*, NativeWidgetIOS*>> map;
  return *map;
}

std::map<UIView*, NativeWidgetIOS*>& ViewMap() {
  static base::NoDestructor<std::map<UIView*, NativeWidgetIOS*>> map;
  return *map;
}

class DummyTooltipManager : public TooltipManager {
 public:
  DummyTooltipManager() = default;
  int GetMaxWidth(const gfx::Point& location) const override { return 300; }
  const gfx::FontList& GetFontList() const override {
    static const base::NoDestructor<gfx::FontList> font_list;
    return *font_list;
  }
  void UpdateTooltip() override {}
  void UpdateTooltipForFocus(View* view) override {}
  void TooltipTextChanged(View* view) override {}
};

UIWindowScene* FirstWindowScene() {
  auto is_window_scene = ^bool(UIScene* scene) {
    return [scene isKindOfClass:[UIWindowScene class]];
  };
  auto is_application_scene = ^bool(UIScene* scene) {
    return is_window_scene(scene) &&
           [scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication];
  };
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if (is_application_scene(scene) &&
        scene.activationState != UISceneActivationStateUnattached) {
      return (UIWindowScene*)scene;
    }
  }
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if (is_application_scene(scene)) {
      return (UIWindowScene*)scene;
    }
  }
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if (is_window_scene(scene) &&
        scene.activationState != UISceneActivationStateUnattached) {
      return (UIWindowScene*)scene;
    }
  }
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if (is_window_scene(scene)) {
      return (UIWindowScene*)scene;
    }
  }
  return nil;
}

BOOL RoleEquals(NSString* role, UISceneSessionRole expected) {
  return [role isEqualToString:expected];
}

BOOL IsExternalDisplayScene(UIWindowScene* scene) {
  if (!scene) {
    return NO;
  }
  NSString* role = scene.session.role;
  if (RoleEquals(role, UIWindowSceneSessionRoleExternalDisplayNonInteractive)) {
    return YES;
  }
#ifdef UIWindowSceneSessionRoleExternalDisplay
  if (RoleEquals(role, UIWindowSceneSessionRoleExternalDisplay)) {
    return YES;
  }
#endif
  return NO;
}

// Prefer the official external display when it is connected so M1 can
// paint on TVOut. Fall back to a large screen, then the app scene.
UIWindowScene* PreferredWindowScene() {
  UIWindowScene* external = nil;
  UIWindowScene* large = nil;
  UIWindowScene* app = FirstWindowScene();
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
      continue;
    }
    UIWindowScene* window_scene = (UIWindowScene*)scene;
    if (IsExternalDisplayScene(window_scene)) {
      external = window_scene;
    }
    CGSize size = window_scene.screen.bounds.size;
    if (size.width >= 1280 && size.height >= 720) {
      large = window_scene;
    }
  }
  return external ? external : (large ? large : app);
}

void LogWindowPlacement(UIWindow* window, const char* why) {
  if (!window) {
    NSLog(@"[DeskBrowser] %s window=nil", why);
    return;
  }
  UIWindowScene* scene = window.windowScene;
  CGRect screen = scene.screen.bounds;
  NSLog(@"[DeskBrowser] %s hidden=%d key=%d frame=%.0f,%.0f %.0fx%.0f "
        @"scene=%s role=%s screen=%.0fx%.0f scale=%.1f screens=%lu scenes=%lu",
        why, window.hidden, window.isKeyWindow, window.frame.origin.x,
        window.frame.origin.y, window.frame.size.width, window.frame.size.height,
        scene ? "Y" : "N",
        scene ? scene.session.role.UTF8String : "(none)", screen.size.width,
        screen.size.height, scene.screen.scale,
        (unsigned long)UIScreen.screens.count,
        (unsigned long)UIApplication.sharedApplication.connectedScenes.count);
}

CGRect RectToCGRect(const gfx::Rect& rect) {
  return CGRectMake(rect.x(), rect.y(), rect.width(), rect.height());
}

}  // namespace

// static
NativeWidgetIOS* NativeWidgetIOS::GetFromNativeView(gfx::NativeView view) {
  UIView* uiview = view.Get();
  if (!uiview) {
    return nullptr;
  }
  auto found = ViewMap().find(uiview);
  return found == ViewMap().end() ? nullptr : found->second;
}

// static
NativeWidgetIOS* NativeWidgetIOS::GetFromNativeWindow(gfx::NativeWindow window) {
  UIWindow* uiwindow = window.Get();
  if (!uiwindow) {
    return nullptr;
  }
  auto found = WindowMap().find(uiwindow);
  return found == WindowMap().end() ? nullptr : found->second;
}

NativeWidgetIOS::NativeWidgetIOS(internal::NativeWidgetDelegate* delegate)
    : delegate_(delegate) {}

NativeWidgetIOS::~NativeWidgetIOS() {
  if (g_capture_widget == this) {
    g_capture_widget = nullptr;
  }
  if (window_) {
    WindowMap().erase(window_);
  }
  if (content_view_) {
    ViewMap().erase(content_view_);
  }
  DestroyCompositor();
  window_.hidden = YES;
  window_ = nil;
  content_view_ = nil;
}

void NativeWidgetIOS::InitNativeWidget(Widget::InitParams params) {
  ownership_ = params.ownership;
  if (ownership_ == Widget::InitParams::NATIVE_WIDGET_OWNS_WIDGET) {
    owned_delegate_ = base::WrapUnique(delegate_.get());
  }
  name_ = params.name;
  type_ = params.type;
  bounds_ = params.bounds.IsEmpty() ? gfx::Rect(0, 0, 800, 600) : params.bounds;

  UIWindowScene* scene = PreferredWindowScene();
  if (scene) {
    window_ = [[UIWindow alloc] initWithWindowScene:scene];
    if (IsExternalDisplayScene(scene) ||
        (scene.screen.bounds.size.width >= 1280 &&
         scene.screen.bounds.size.height >= 720)) {
      CGRect screen_bounds = scene.screen.bounds;
      bounds_ = gfx::Rect(screen_bounds.origin.x, screen_bounds.origin.y,
                          screen_bounds.size.width, screen_bounds.size.height);
    }
  } else {
    window_ = [[UIWindow alloc] initWithFrame:RectToCGRect(bounds_)];
  }
  window_.frame = RectToCGRect(bounds_);
  window_.backgroundColor = [UIColor colorWithRed:0.13
                                            green:0.14
                                             blue:0.16
                                            alpha:1.0];
  content_view_ = [[DeskBrowserViewsContentView alloc]
      initWithFrame:window_.bounds];
  content_view_.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  window_.rootViewController = [[UIViewController alloc] init];
  window_.rootViewController.view = content_view_;

  WindowMap()[window_] = this;
  ViewMap()[content_view_] = this;

  tooltip_manager_ = std::make_unique<DummyTooltipManager>();
  CreateCompositor(params);

  if (delegate_) {
    delegate_->OnNativeWidgetCreated();
  }
}

void NativeWidgetIOS::CreateCompositor(const Widget::InitParams& params) {
  CHECK(ViewsDelegate::GetInstance());
  ui::ContextFactory* context_factory =
      ViewsDelegate::GetInstance()->GetContextFactory();
  CHECK(context_factory);

  bool translucent =
      params.opacity == Widget::InitParams::WindowOpacity::kTranslucent;
  root_layer_ = ui::Layer::Create(params.layer_type);
  root_layer_->SetName(name_.empty() ? "NativeWidgetIOS" : name_);
  root_layer_->set_delegate(this);
  root_layer_->SetFillsBoundsOpaquely(!translucent);
  root_layer_->SetBounds(gfx::Rect(bounds_.size()));

  compositor_ = std::make_unique<ui::Compositor>(
      context_factory->AllocateFrameSinkId(), context_factory,
      base::SingleThreadTaskRunner::GetCurrentDefault(),
      false /* enable_pixel_canvas */);
  auto* host = (DeskBrowserViewsContentView*)content_view_;
  NSLog(@"[DeskBrowser] SetAcceleratedWidget handle=%llu view_bounds=%.1fx%.1f "
        @"window_frame=%.1f,%.1f %.1fx%.1f",
        (unsigned long long)host.viewHandle, content_view_.bounds.size.width,
        content_view_.bounds.size.height, window_.frame.origin.x,
        window_.frame.origin.y, window_.frame.size.width,
        window_.frame.size.height);
  LogWindowPlacement(window_, "InitNativeWidget");
  compositor_->SetAcceleratedWidget(host.viewHandle);
  UpdateCompositorSurface();
  compositor_->SetBackgroundColor(translucent ? SK_ColorTRANSPARENT
                                              : SK_ColorWHITE);
  compositor_->SetRootLayer(root_layer_.get());
  compositor_->SetVisible(false);
}

void NativeWidgetIOS::DestroyCompositor() {
  if (root_layer_) {
    root_layer_->set_delegate(nullptr);
  }
  if (compositor_) {
    compositor_->SetRootLayer(nullptr);
    compositor_->SetVisible(false);
    compositor_->SetAcceleratedWidget(gfx::kNullAcceleratedWidget);
  }
  compositor_.reset();
  root_layer_.reset();
}

void NativeWidgetIOS::SyncWindowFrame() {
  if (!window_) {
    return;
  }
  window_.frame = RectToCGRect(bounds_);
  if (root_layer_) {
    root_layer_->SetBounds(gfx::Rect(bounds_.size()));
  }
  if (compositor_) {
    UpdateCompositorSurface();
  }
}

void NativeWidgetIOS::UpdateCompositorSurface() {
  if (!compositor_) {
    return;
  }
  float scale = 1.0f;
  if (window_ && window_.screen) {
    scale = window_.screen.scale;
    if (content_view_ && content_view_.layer) {
      content_view_.layer.contentsScale = scale;
    }
  }
  const gfx::Size size_pixels = gfx::ScaleToCeiledSize(bounds_.size(), scale);
  if (size_pixels == compositor_size_pixels_ && scale == compositor_scale_ &&
      local_surface_id_allocator_.HasValidLocalSurfaceId()) {
    return;
  }
  compositor_size_pixels_ = size_pixels;
  compositor_scale_ = scale;
  local_surface_id_allocator_.GenerateId();
  compositor_->SetScaleAndSize(
      scale, size_pixels,
      local_surface_id_allocator_.GetCurrentLocalSurfaceId());
}

void NativeWidgetIOS::OnWidgetInitDone() {}

void NativeWidgetIOS::ReparentNativeViewImpl(gfx::NativeView new_parent) {
  NOTIMPLEMENTED();
}

std::unique_ptr<FrameView> NativeWidgetIOS::CreateFrameView() {
  return nullptr;
}

bool NativeWidgetIOS::ShouldUseNativeFrame() const {
  return false;
}

bool NativeWidgetIOS::ShouldWindowContentsBeTransparent() const {
  return false;
}

void NativeWidgetIOS::FrameTypeChanged() {}

Widget* NativeWidgetIOS::GetWidget() {
  return delegate_ ? delegate_->AsWidget() : nullptr;
}

const Widget* NativeWidgetIOS::GetWidget() const {
  return delegate_ ? delegate_->AsWidget() : nullptr;
}

gfx::NativeView NativeWidgetIOS::GetNativeView() const {
  return gfx::NativeView(content_view_);
}

gfx::NativeWindow NativeWidgetIOS::GetNativeWindow() const {
  return gfx::NativeWindow(window_);
}

Widget* NativeWidgetIOS::GetTopLevelWidget() {
  return GetWidget();
}

const ui::Compositor* NativeWidgetIOS::GetCompositor() const {
  return compositor_.get();
}

const ui::Layer* NativeWidgetIOS::GetLayer() const {
  return root_layer_.get();
}

void NativeWidgetIOS::ReorderNativeViews() {}

void NativeWidgetIOS::ViewRemoved(View* view) {}

void NativeWidgetIOS::SetNativeWindowProperty(const char* name, void* value) {
  if (value) {
    native_window_properties_[name] = value;
  } else {
    native_window_properties_.erase(name);
  }
}

void* NativeWidgetIOS::GetNativeWindowProperty(const char* name) const {
  auto it = native_window_properties_.find(name);
  return it == native_window_properties_.end() ? nullptr : it->second.get();
}

TooltipManager* NativeWidgetIOS::GetTooltipManager() const {
  return tooltip_manager_.get();
}

void NativeWidgetIOS::SetCapture() {
  g_capture_widget = this;
  has_capture_ = true;
}

void NativeWidgetIOS::ReleaseCapture() {
  if (g_capture_widget == this) {
    g_capture_widget = nullptr;
  }
  has_capture_ = false;
}

bool NativeWidgetIOS::HasCapture() const {
  return has_capture_;
}

ui::InputMethod* NativeWidgetIOS::GetInputMethod() {
  if (!input_method_) {
    input_method_ = ui::CreateInputMethod(this, gfx::kNullAcceleratedWidget);
    input_method_->OnFocus();
  }
  return input_method_.get();
}

void NativeWidgetIOS::CenterWindow(const gfx::Size& size) {
  SetSize(size);
}

void NativeWidgetIOS::GetWindowPlacement(
    gfx::Rect* bounds,
    ui::mojom::WindowShowState* show_state) const {
  if (bounds) {
    *bounds = bounds_;
  }
  if (show_state) {
    *show_state = visible_ ? ui::mojom::WindowShowState::kNormal
                           : ui::mojom::WindowShowState::kDefault;
  }
}

bool NativeWidgetIOS::SetWindowTitle(const std::u16string& title) {
  return true;
}

void NativeWidgetIOS::SetWindowIcons(const gfx::ImageSkia& window_icon,
                                     const gfx::ImageSkia& app_icon) {}

void NativeWidgetIOS::InitModalType(ui::mojom::ModalType modal_type) {}

void NativeWidgetIOS::SetBackgroundColor(SkColor background_color) {
  if (compositor_) {
    compositor_->SetBackgroundColor(background_color);
  }
}

gfx::Rect NativeWidgetIOS::GetWindowBoundsInScreen() const {
  return bounds_;
}

gfx::Rect NativeWidgetIOS::GetClientAreaBoundsInScreen() const {
  return bounds_;
}

gfx::Rect NativeWidgetIOS::GetRestoredBounds() const {
  return bounds_;
}

std::string NativeWidgetIOS::GetWorkspace() const {
  return std::string();
}

void NativeWidgetIOS::SetBounds(const gfx::Rect& bounds) {
  bounds_ = bounds;
  SyncWindowFrame();
  // Widget::SetBounds only forwards to the native widget. On Mac, AppKit
  // then calls back OnNativeWidgetSizeChanged so RootView is resized and
  // paints. iOS has no such callback unless we fire it here — without it
  // RootView stays 0x0, the compositor commits 0 quads, and the CA tree
  // is an empty wrapper. Notify even when the window size is unchanged,
  // because the first SetBounds (from SetInitialBoundsForFramelessWindow)
  // often matches the init bounds while RootView is still 0x0.
  if (Widget* widget = GetWidget()) {
    if (!widget->GetRootView() ||
        widget->GetRootView()->size() != bounds_.size()) {
      widget->OnNativeWidgetSizeChanged(bounds_.size());
    }
  }
  if (compositor_ && visible_) {
    compositor_->ScheduleDraw();
  }
}

void NativeWidgetIOS::SetBoundsConstrained(const gfx::Rect& bounds) {
  SetBounds(ConstrainBoundsToDisplayWorkArea(bounds));
}

void NativeWidgetIOS::SetSize(const gfx::Size& size) {
  SetBounds(gfx::Rect(bounds_.origin(), size));
}

void NativeWidgetIOS::StackAbove(gfx::NativeView native_view) {}

void NativeWidgetIOS::StackAtTop() {
  if (window_) {
    [window_ makeKeyAndVisible];
  }
}

bool NativeWidgetIOS::IsStackedAbove(gfx::NativeView native_view) {
  return false;
}

void NativeWidgetIOS::SetShape(std::unique_ptr<Widget::ShapeRects> shape) {}

void NativeWidgetIOS::Close() {
  if (closing_) {
    return;
  }
  closing_ = true;
  Hide();
  if (delegate_) {
    delegate_->OnNativeWidgetDestroying();
  }
  CloseNow();
}

void NativeWidgetIOS::CloseNow() {
  closing_ = true;
  Hide();
  if (delegate_) {
    delegate_->OnNativeWidgetDestroyed();
  }
  if (ownership_ == Widget::InitParams::NATIVE_WIDGET_OWNS_WIDGET) {
    delete this;
  }
}

void NativeWidgetIOS::Show(ui::mojom::WindowShowState show_state,
                           const gfx::Rect& restore_bounds) {
  visible_ = true;
  active_ = true;
  if (window_) {
    UIWindowScene* preferred = PreferredWindowScene();
    if (preferred && window_.windowScene != preferred) {
      window_.windowScene = preferred;
      if (IsExternalDisplayScene(preferred) ||
          (preferred.screen.bounds.size.width >= 1280 &&
           preferred.screen.bounds.size.height >= 720)) {
        CGRect screen_bounds = preferred.screen.bounds;
        bounds_ = gfx::Rect(screen_bounds.origin.x, screen_bounds.origin.y,
                            screen_bounds.size.width, screen_bounds.size.height);
        SyncWindowFrame();
      }
    }
    window_.hidden = NO;
    [window_ makeKeyAndVisible];
    LogWindowPlacement(window_, "Show");
  }
  if (root_layer_) {
    root_layer_->SetVisible(true);
  }
  if (compositor_) {
    compositor_->SetVisible(true);
    compositor_->ScheduleDraw();
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce([] {
          NSLog(@"[DeskBrowser] compositor UI task ran after Show");
        }));
    // The GPU presenter attaches the compositor CALayer asynchronously on
    // the main queue; the first ScheduleDraw can run before that attach.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<NativeWidgetIOS> self) {
                         if (self && self->compositor_) {
                           self->compositor_->ScheduleDraw();
                           NSLog(@"[DeskBrowser] delayed ScheduleDraw after Show");
                         }
                       },
                       weak_factory_.GetWeakPtr()),
        base::Milliseconds(100));
  }
  if (delegate_) {
    delegate_->OnNativeWidgetVisibilityChanged(true);
    delegate_->OnNativeWidgetActivationChanged(true);
  }
  if (GetWidget()) {
    GetWidget()->GetRootView()->SchedulePaint();
  }
}

void NativeWidgetIOS::Hide() {
  visible_ = false;
  active_ = false;
  if (window_) {
    window_.hidden = YES;
  }
  if (root_layer_) {
    root_layer_->SetVisible(false);
  }
  if (compositor_) {
    compositor_->SetVisible(false);
  }
  if (delegate_) {
    delegate_->OnNativeWidgetVisibilityChanged(false);
  }
}

bool NativeWidgetIOS::IsVisible() const {
  return visible_;
}

bool NativeWidgetIOS::IsVisibleOnScreen() const {
  return visible_;
}

void NativeWidgetIOS::Activate() {
  active_ = true;
  if (window_) {
    [window_ makeKeyAndVisible];
  }
  if (delegate_) {
    delegate_->OnNativeWidgetActivationChanged(true);
  }
}

void NativeWidgetIOS::Deactivate() {
  active_ = false;
  if (delegate_) {
    delegate_->OnNativeWidgetActivationChanged(false);
  }
}

bool NativeWidgetIOS::IsActive() const {
  return active_;
}

void NativeWidgetIOS::SetZOrderLevel(ui::ZOrderLevel order) {
  z_order_ = order;
}

ui::ZOrderLevel NativeWidgetIOS::GetZOrderLevel() const {
  return z_order_;
}


void NativeWidgetIOS::SetVisibleOnAllWorkspaces(bool always_visible) {}

bool NativeWidgetIOS::IsVisibleOnAllWorkspaces() const {
  return false;
}


void NativeWidgetIOS::Maximize() {}

void NativeWidgetIOS::Minimize() {}

bool NativeWidgetIOS::IsMaximized() const {
  return false;
}

bool NativeWidgetIOS::IsMinimized() const {
  return false;
}

void NativeWidgetIOS::Restore() {}

void NativeWidgetIOS::SetFullscreen(bool fullscreen, int64_t target_display_id) {
}

bool NativeWidgetIOS::IsFullscreen() const {
  return false;
}

void NativeWidgetIOS::SetCanAppearInExistingFullscreenSpaces(
    bool can_appear_in_existing_fullscreen_spaces) {}

void NativeWidgetIOS::SetOpacity(float opacity) {
  if (window_) {
    window_.alpha = opacity;
  }
}

void NativeWidgetIOS::SetAspectRatio(const gfx::SizeF& aspect_ratio,
                                     const gfx::Size& excluded_margin) {}

void NativeWidgetIOS::FlashFrame(bool flash) {}

void NativeWidgetIOS::RunDragDropLoop(std::unique_ptr<ui::OSExchangeData> data,
                                      const gfx::Point& location,
                                      int operation,
                                      ui::mojom::DragEventSource source) {
  NOTIMPLEMENTED();
}

void NativeWidgetIOS::CancelDragDropLoop(View* view) {}

void NativeWidgetIOS::SchedulePaintInRect(const gfx::Rect& rect) {
  if (root_layer_) {
    root_layer_->SchedulePaint(rect);
  }
  if (compositor_) {
    compositor_->ScheduleDraw();
  }
}

void NativeWidgetIOS::ScheduleLayout() {
  if (GetWidget()) {
    GetWidget()->GetRootView()->InvalidateLayout();
  }
}

void NativeWidgetIOS::SetCursor(const ui::Cursor& cursor) {}

bool NativeWidgetIOS::IsMouseEventsEnabled() const {
  return true;
}

bool NativeWidgetIOS::IsMouseButtonDown() const {
  return false;
}

void NativeWidgetIOS::ClearNativeFocus() {}

gfx::Rect NativeWidgetIOS::GetWorkAreaBoundsInScreen() const {
  if (auto* screen = display::Screen::Get()) {
    return screen->GetPrimaryDisplay().work_area();
  }
  return bounds_;
}

Widget::MoveLoopResult NativeWidgetIOS::RunMoveLoop(
    const gfx::Vector2d& drag_offset,
    Widget::MoveLoopSource source,
    Widget::MoveLoopEscapeBehavior escape_behavior) {
  return Widget::MoveLoopResult::kCanceled;
}

void NativeWidgetIOS::EndMoveLoop() {}

void NativeWidgetIOS::SetVisibilityChangedAnimationsEnabled(bool value) {}

void NativeWidgetIOS::SetVisibilityAnimationDuration(
    const base::TimeDelta& duration) {}

void NativeWidgetIOS::SetVisibilityAnimationTransition(
    Widget::VisibilityTransition transition) {}

ui::GestureRecognizer* NativeWidgetIOS::GetGestureRecognizer() {
  return nullptr;
}

ui::GestureConsumer* NativeWidgetIOS::GetGestureConsumer() {
  return nullptr;
}

void NativeWidgetIOS::OnSizeConstraintsChanged() {}

void NativeWidgetIOS::OnNativeViewHierarchyWillChange() {}

void NativeWidgetIOS::OnNativeViewHierarchyChanged() {}


bool NativeWidgetIOS::SetAllowScreenshots(bool allow) {
  screenshots_allowed_ = allow;
  return true;
}

bool NativeWidgetIOS::AreScreenshotsAllowed() {
  return screenshots_allowed_;
}

bool NativeWidgetIOS::IsDesktopNativeWidget() const {
  return true;
}

std::string NativeWidgetIOS::GetName() const {
  return name_;
}

base::WeakPtr<internal::NativeWidgetPrivate> NativeWidgetIOS::GetWeakPtr() {
  return weak_factory_.GetWeakPtr();
}

void NativeWidgetIOS::OnPaintLayer(const ui::PaintContext& context) {
  static int paints = 0;
  if (paints < 8) {
    paints++;
    gfx::Size root_size;
    if (Widget* widget = GetWidget()) {
      if (View* root = widget->GetRootView()) {
        root_size = root->size();
      }
    }
    NSLog(@"[DeskBrowser] OnPaintLayer #%d layer=%dx%d root_view=%dx%d",
          paints, bounds_.width(), bounds_.height(), root_size.width(),
          root_size.height());
  }
  if (Widget* widget = GetWidget()) {
    widget->OnNativeWidgetPaint(context);
  }
}

void NativeWidgetIOS::OnDeviceScaleFactorChanged(float old_device_scale_factor,
                                                 float new_device_scale_factor) {
  if (Widget* widget = GetWidget()) {
    widget->DeviceScaleFactorChanged(old_device_scale_factor,
                                     new_device_scale_factor);
  }
}

ui::EventDispatchDetails NativeWidgetIOS::DispatchKeyEventPostIME(
    ui::KeyEvent* key) {
  if (Widget* widget = GetWidget()) {
    widget->OnKeyEvent(key);
  }
  return ui::EventDispatchDetails();
}

namespace internal {

NativeWidgetPrivate* NativeWidgetPrivate::CreateNativeWidget(
    internal::NativeWidgetDelegate* delegate) {
  return new NativeWidgetIOS(delegate);
}

NativeWidgetPrivate* NativeWidgetPrivate::GetNativeWidgetForNativeView(
    gfx::NativeView native_view) {
  return NativeWidgetIOS::GetFromNativeView(native_view);
}

NativeWidgetPrivate* NativeWidgetPrivate::GetNativeWidgetForNativeWindow(
    gfx::NativeWindow native_window) {
  return NativeWidgetIOS::GetFromNativeWindow(native_window);
}

NativeWidgetPrivate* NativeWidgetPrivate::GetTopLevelNativeWidget(
    gfx::NativeView native_view) {
  NativeWidgetPrivate* widget = GetNativeWidgetForNativeView(native_view);
  return widget;
}

Widget::Widgets NativeWidgetPrivate::GetAllChildWidgets(
    gfx::NativeView native_view) {
  Widget::Widgets widgets;
  if (auto* native = GetNativeWidgetForNativeView(native_view)) {
    if (Widget* widget = native->GetWidget()) {
      widgets.insert(widget);
    }
  }
  return widgets;
}

Widget::Widgets NativeWidgetPrivate::GetAllOwnedWidgets(
    gfx::NativeView native_view) {
  return GetAllChildWidgets(native_view);
}

void NativeWidgetPrivate::ReparentNativeView(gfx::NativeView child,
                                             gfx::NativeView new_parent) {
  if (auto* native = GetNativeWidgetForNativeView(child)) {
    native->ReparentNativeViewImpl(new_parent);
  }
}

gfx::NativeView NativeWidgetPrivate::GetGlobalCapture(
    gfx::NativeView native_view) {
  if (g_capture_widget) {
    return g_capture_widget->GetNativeView();
  }
  return gfx::NativeView();
}

}  // namespace internal
}  // namespace views
