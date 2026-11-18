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
#include "ui/accelerated_widget_mac/ca_layer_frame_sink_provider.h"
#include "ui/accelerated_widget_mac/display_ca_layer_tree.h"
#include "ui/base/ime/input_method.h"
#include "ui/base/ime/init/input_method_factory.h"
#include "ui/compositor/compositor.h"
#include "ui/compositor/layer.h"
#include "ui/compositor/paint_context.h"
#include "ui/display/screen.h"
#include "ui/gfx/font_list.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/views/view.h"
#include "ui/views/views_delegate.h"
#include "ui/views/widget/tooltip_manager.h"
#include "ui/views/widget/widget_delegate.h"
#include "ui/base/dragdrop/os_exchange_data.h"

@interface DeskBrowserViewsContentView : CALayerFrameSinkProvider
- (ui::DisplayCALayerTree*)displayCALayerTree;
@end

@implementation DeskBrowserViewsContentView {
  std::unique_ptr<ui::DisplayCALayerTree> _tree;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.opaque = YES;
    self.backgroundColor = [UIColor colorWithRed:0.13
                                           green:0.14
                                            blue:0.16
                                           alpha:1.0];
    _tree = std::make_unique<ui::DisplayCALayerTree>(self.layer);
  }
  return self;
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
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]] &&
        scene.activationState != UISceneActivationStateUnattached) {
      return (UIWindowScene*)scene;
    }
  }
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:[UIWindowScene class]]) {
      return (UIWindowScene*)scene;
    }
  }
  return nil;
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

  UIWindowScene* scene = FirstWindowScene();
  if (scene) {
    window_ = [[UIWindow alloc] initWithWindowScene:scene];
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
  auto* provider = (CALayerFrameSinkProvider*)content_view_;
  compositor_->SetAcceleratedWidget(provider.viewHandle);
  float scale = window_.screen ? window_.screen.scale : 1.0f;
  compositor_->SetScaleAndSize(scale, bounds_.size(), viz::LocalSurfaceId());
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
    float scale = window_.screen ? window_.screen.scale : 1.0f;
    compositor_->SetScaleAndSize(scale, bounds_.size(), viz::LocalSurfaceId());
  }
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
}

void NativeWidgetIOS::SetBoundsConstrained(const gfx::Rect& bounds) {
  SetBounds(ConstrainBoundsToDisplayWorkArea(bounds));
}

void NativeWidgetIOS::SetSize(const gfx::Size& size) {
  bounds_.set_size(size);
  SyncWindowFrame();
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
    window_.hidden = NO;
    [window_ makeKeyAndVisible];
  }
  if (root_layer_) {
    root_layer_->SetVisible(true);
  }
  if (compositor_) {
    compositor_->SetVisible(true);
    compositor_->ScheduleDraw();
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
