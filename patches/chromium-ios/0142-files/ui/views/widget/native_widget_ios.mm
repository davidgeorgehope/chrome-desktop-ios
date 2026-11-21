// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ui/views/widget/native_widget_ios.h"

#import <UIKit/UIKit.h>

#include <algorithm>
#include <map>
#include <string_view>
#include <tuple>
#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
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
#include "ui/display/ios/phone_desktop_ios.h"
#include "ui/display/screen.h"
#include "ui/events/event.h"
#include "ui/events/gestures/gesture_recognizer_impl_mac.h"
#include "ui/views/focus/focus_manager.h"
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

// Root controller of every widget window. On the on-phone desktop the scene's
// orientation must follow the phone input host's lock, whichever window iOS
// asks.
@interface DeskBrowserViewsWindowController : UIViewController
@end

@implementation DeskBrowserViewsWindowController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  const display::PhoneDesktopForIOS& phone = display::GetPhoneDesktopForIOS();
  if (phone.active && phone.landscape_right_only) {
    return UIInterfaceOrientationMaskLandscapeRight;
  }
  return UIInterfaceOrientationMaskAllButUpsideDown;
}
- (BOOL)prefersStatusBarHidden {
  return display::GetPhoneDesktopForIOS().active;
}
- (BOOL)prefersHomeIndicatorAutoHidden {
  return YES;
}
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
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  for (CALayer* sub in self.layer.sublayers) {
    // Only stretch compositor layers. Backing layers of native subviews
    // (e.g. the WebContents UIScrollView placed by NativeViewHostIOS) keep
    // the frame Views gave them.
    if ([sub.delegate isKindOfClass:[UIView class]]) {
      continue;
    }
    if (!CGRectEqualToRect(sub.frame, self.layer.bounds)) {
      sub.frame = self.layer.bounds;
    }
    if (sub.contentsScale != self.layer.contentsScale) {
      sub.contentsScale = self.layer.contentsScale;
    }
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

// Re-homes every widget window when a UIWindowScene connects or activates.
// Browser windows are created during willFinishLaunching, before UIKit has
// connected any scene (including the TVOut external-display scene).
void RehomeAllWidgets(const char* why) {
  std::vector<NativeWidgetIOS*> widgets;
  for (const auto& entry : WindowMap()) {
    widgets.push_back(entry.second);
  }
  for (NativeWidgetIOS* widget : widgets) {
    widget->MoveToPreferredScene(why);
  }
}

void InstallSceneObserverOnce() {
  static bool installed = false;
  if (installed) {
    return;
  }
  installed = true;
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  for (NSNotificationName name :
       @[ UISceneWillConnectNotification, UISceneDidActivateNotification ]) {
    [center addObserverForName:name
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification*) {
                      // Let UIKit finish connecting before re-homing.
                      dispatch_async(dispatch_get_main_queue(), ^{
                        RehomeAllWidgets("SceneConnected");
                      });
                    }];
  }
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
bool g_require_external_display = false;

bool PhoneDesktopActive() {
  return display::GetPhoneDesktopForIOS().active;
}

// Whether a top-level window on |scene| fills it like a maximized desktop
// window, and the rect it fills.
bool FillsDesktop(UIWindowScene* scene) {
  if (IsExternalDisplayScene(scene)) {
    return true;
  }
  if (PhoneDesktopActive()) {
    return true;
  }
  return scene.screen.bounds.size.width >= 1280 &&
         scene.screen.bounds.size.height >= 720;
}

gfx::Rect DesktopRect(UIWindowScene* scene) {
  if (PhoneDesktopActive() && !IsExternalDisplayScene(scene)) {
    return gfx::Rect(display::GetPhoneDesktopForIOS().size);
  }
  CGRect b = scene.screen.bounds;
  return gfx::Rect(b.origin.x, b.origin.y, b.size.width, b.size.height);
}

UIWindowScene* PreferredWindowScene() {
  // No external display: the desktop is on the phone's own scene. The phone
  // input host decides (it sets the phone desktop active) so that widgets
  // and input switch together.
  if (PhoneDesktopActive()) {
    return FirstWindowScene();
  }
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
  if (g_require_external_display) {
    return external;
  }
  return external ? external : (large ? large : app);
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

// static
bool NativeWidgetIOS::DispatchTrackpadMouseEvent(gfx::NativeWindow window,
                                                 ui::MouseEvent* event) {
  NativeWidgetIOS* native = GetFromNativeWindow(window);
  if (!native || !native->delegate_) {
    return false;
  }
  native->delegate_->OnMouseEvent(event);
  return true;
}

namespace {
std::vector<NativeWidgetIOS::KeyEventMonitor*>& KeyEventMonitors() {
  static base::NoDestructor<std::vector<NativeWidgetIOS::KeyEventMonitor*>>
      monitors;
  return *monitors;
}
}  // namespace

// static
void NativeWidgetIOS::AddKeyEventMonitor(KeyEventMonitor* monitor) {
  KeyEventMonitors().push_back(monitor);
}

// static
void NativeWidgetIOS::RemoveKeyEventMonitor(KeyEventMonitor* monitor) {
  std::erase(KeyEventMonitors(), monitor);
}

// static
bool NativeWidgetIOS::HasKeyEventMonitor() {
  return !KeyEventMonitors().empty();
}

// static
void NativeWidgetIOS::ExternalSceneGeometryChanged() {
  RehomeAllWidgets("SceneGeometryChanged");
  [NSNotificationCenter.defaultCenter
      postNotificationName:@"NativeWidgetIOSSceneGeometryDidChange"
                    object:nil];
}

void NativeWidgetIOS::SetRequireExternalDisplay(bool require) {
  g_require_external_display = require;
}

// static
gfx::NativeWindow NativeWidgetIOS::GetCaptureWindow() {
  if (!g_capture_widget || !g_capture_widget->window_) {
    return gfx::NativeWindow();
  }
  return gfx::NativeWindow(g_capture_widget->window_);
}

// static
bool NativeWidgetIOS::DispatchTrackpadKeyEvent(gfx::NativeWindow window,
                                               ui::KeyEvent* event) {
  // Newest monitor first; a monitor may remove itself while handling.
  std::vector<KeyEventMonitor*> monitors = KeyEventMonitors();
  for (auto it = monitors.rbegin(); it != monitors.rend(); ++it) {
    if (std::ranges::contains(KeyEventMonitors(), *it) &&
        (*it)->OnTrackpadKeyEvent(event)) {
      return true;
    }
  }
  NativeWidgetIOS* native = GetFromNativeWindow(window);
  if (!native) {
    return false;
  }
  if (ui::InputMethod* input_method = native->GetInputMethod()) {
    std::ignore = input_method->DispatchKeyEvent(event);
  } else {
    std::ignore = native->DispatchKeyEventPostIME(event);
  }
  return true;
}

NativeWidgetIOS::NativeWidgetIOS(internal::NativeWidgetDelegate* delegate)
    : delegate_(delegate) {}

NativeWidgetIOS::~NativeWidgetIOS() {
  StopObservingFocus();
  if (g_capture_widget == this) {
    g_capture_widget = nullptr;
  }
  for (auto& entry : ViewMap()) {
    if (entry.second->parent_ == this) {
      entry.second->parent_ = nullptr;
    }
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
  // With NATIVE_WIDGET_OWNS_WIDGET, |delegate_| points at |owned_delegate_|.
  // Clear it before the Widget is freed so the raw_ptr never dangles.
  std::unique_ptr<internal::NativeWidgetDelegate> owned =
      std::move(owned_delegate_);
  delegate_ = nullptr;
  owned.reset();
}

void NativeWidgetIOS::InitNativeWidget(Widget::InitParams params) {
  ownership_ = params.ownership;
  if (ownership_ == Widget::InitParams::NATIVE_WIDGET_OWNS_WIDGET) {
    owned_delegate_ = base::WrapUnique(delegate_.get());
  }
  name_ = params.name;
  type_ = params.type;
  parent_ = params.parent ? GetFromNativeView(params.parent) : nullptr;
  if (parent_ == this) {
    parent_ = nullptr;
  }
  bounds_ = params.bounds.IsEmpty() ? gfx::Rect(0, 0, 800, 600) : params.bounds;

  UIWindowScene* scene = PreferredWindowScene();
  if (scene) {
    window_ = [[UIWindow alloc] initWithWindowScene:scene];
    // Only top-level windows are maximized on a desktop-sized screen. Menus,
    // bubbles and popups keep the bounds Views asked for.
    if (type_ == Widget::InitParams::TYPE_WINDOW && !parent_ &&
        FillsDesktop(scene)) {
      bounds_ = DesktopRect(scene);
    }
  } else {
    window_ = [[UIWindow alloc] initWithFrame:RectToCGRect(bounds_)];
  }
  ApplyWindowGeometry();
  window_.backgroundColor = [UIColor colorWithRed:0.13
                                            green:0.14
                                             blue:0.16
                                            alpha:1.0];
  content_view_ = [[DeskBrowserViewsContentView alloc]
      initWithFrame:window_.bounds];
  content_view_.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  window_.rootViewController = [[DeskBrowserViewsWindowController alloc] init];
  window_.rootViewController.view = content_view_;

  WindowMap()[window_] = this;
  ViewMap()[content_view_] = this;
  InstallSceneObserverOnce();

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
    // As NativeWidgetMac: release, not re-set; SetAcceleratedWidget may only
    // be called once and CHECKs if the widget is still valid.
    std::ignore = compositor_->ReleaseAcceleratedWidget();
  }
  compositor_.reset();
  root_layer_.reset();
}

bool NativeWidgetIOS::OnPhoneDesktop() const {
  return window_ && window_.windowScene && PhoneDesktopActive() &&
         !IsExternalDisplayScene(window_.windowScene);
}

void NativeWidgetIOS::ApplyWindowGeometry() {
  if (!window_) {
    return;
  }
  window_.transform = CGAffineTransformIdentity;
  if (!OnPhoneDesktop()) {
    window_.frame = RectToCGRect(bounds_);
    return;
  }
  // The window keeps its desktop size in points (so Views, the compositor
  // and web content all lay out in desktop DIPs) and is scaled onto the
  // panel: panel = origin + zoom * desktop.
  const display::PhoneDesktopForIOS& phone = display::GetPhoneDesktopForIOS();
  window_.bounds = CGRectMake(0, 0, bounds_.width(), bounds_.height());
  window_.center =
      CGPointMake(phone.origin.x() +
                      (bounds_.x() + bounds_.width() / 2.0) * phone.zoom,
                  phone.origin.y() +
                      (bounds_.y() + bounds_.height() / 2.0) * phone.zoom);
  window_.transform = CGAffineTransformMakeScale(phone.zoom, phone.zoom);
}

void NativeWidgetIOS::OrderWindowFront() {
  if (!window_) {
    return;
  }
  if (OnPhoneDesktop()) {
    window_.hidden = NO;
    return;
  }
  window_.hidden = NO;
  [window_ makeKeyAndVisible];
}

// static
void NativeWidgetIOS::PhoneDesktopViewportChanged() {
  for (const auto& entry : WindowMap()) {
    entry.second->ApplyWindowGeometry();
  }
}

void NativeWidgetIOS::SyncWindowFrame() {
  if (!window_) {
    return;
  }
  ApplyWindowGeometry();
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

void NativeWidgetIOS::OnWidgetInitDone() {
  Widget* widget = GetWidget();
  // Menus and bubbles keep their InitParams bounds and may never call
  // SetBounds. Without the size notification their RootView stays 0x0.
  if (widget && widget->GetRootView() &&
      widget->GetRootView()->size() != bounds_.size()) {
    widget->OnNativeWidgetSizeChanged(bounds_.size());
  }
  FocusManager* fm = widget ? widget->GetFocusManager() : nullptr;
  if (fm && !observed_focus_manager_) {
    fm->AddFocusChangeListener(this);
    observed_focus_manager_ = fm;
  }
}

void NativeWidgetIOS::StopObservingFocus() {
  if (observed_focus_manager_) {
    observed_focus_manager_->RemoveFocusChangeListener(this);
    observed_focus_manager_ = nullptr;
  }
}

namespace {
bool HostsNativeView(const View* view) {
  if (!view) {
    return false;
  }
  if (std::string_view(view->GetClassName()) == "NativeViewHost") {
    return true;
  }
  for (const View* child : view->children()) {
    if (HostsNativeView(child)) {
      return true;
    }
  }
  return false;
}
}  // namespace

// Each UIWindow keeps its own first responder, so a hosted native view (the
// WebContents' RenderWidget UIView) stays first responder after Views focus
// moves to e.g. the omnibox, and its layoutSubviews -> SetActive(true) then
// refocuses the WebContents, stealing Views focus back. Mirror
// NativeWidgetMacNSWindowHost::OnDidChangeFocus: when focus lands on a plain
// Views view, resign the native first responder in this window.
void NativeWidgetIOS::OnDidChangeFocus(View* focused_before,
                                       View* focused_now) {
  if (!window_ || HostsNativeView(focused_now)) {
    return;
  }
  [window_ endEditing:YES];
}

void NativeWidgetIOS::ReparentNativeViewImpl(gfx::NativeView new_parent) {
  NativeWidgetIOS* parent = GetFromNativeView(new_parent);
  // Refuse cycles: the new parent must not be this widget or one it owns.
  for (NativeWidgetIOS* p = parent; p; p = p->parent_) {
    if (p == this) {
      return;
    }
  }
  parent_ = parent;
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
  OrderWindowFront();
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
  // Widget::CloseWithReason() is on the Widget's stack, so destroying the
  // Widget synchronously trips CHECK(!on_call_stack_). Hide now and destroy
  // asynchronously, as DesktopNativeWidgetAura and NativeWidgetMac do.
  Hide();
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&NativeWidgetIOS::CloseNow,
                                weak_factory_.GetWeakPtr()));
}

void NativeWidgetIOS::ClientDestroyedWidget() {
  // CLIENT_OWNS_WIDGET: the Widget is in its destructor. Drop every pointer
  // into it now; the deferred CloseNow() (posted by Close()) and walks over
  // ViewMap() (GetAllOwnedWidgets, accessibility title updates) must never
  // see the freed Widget.
  StopObservingFocus();
  if (g_capture_widget == this) {
    g_capture_widget = nullptr;
  }
  delegate_ = nullptr;
}

void NativeWidgetIOS::CloseNow() {
  if (destroyed_) {
    return;
  }
  closing_ = true;
  Hide();
  // Widget::CloseNow() comes straight here (e.g. StatusBubbleViews), so the
  // destroying notification must be sent here, once, before destroyed.
  if (delegate_ && !destroying_notified_) {
    destroying_notified_ = true;
    delegate_->OnNativeWidgetDestroying();
  }
  StopObservingFocus();
  destroyed_ = true;
  // As NativeWidgetMac::WindowDestroyed: the native widget owns itself under
  // NATIVE_WIDGET_OWNS_WIDGET and CLIENT_OWNS_WIDGET. Keeping a closed
  // CLIENT_OWNS_WIDGET native widget alive left it in ViewMap() with a
  // dangling delegate_, which crashed the next GetAllOwnedWidgets() walk
  // (new tab -> BrowserView::UpdateTitleBar -> accessible window title).
  const bool delete_this =
      ownership_ == Widget::InitParams::NATIVE_WIDGET_OWNS_WIDGET ||
      ownership_ == Widget::InitParams::CLIENT_OWNS_WIDGET;
  if (delegate_) {
    delegate_->OnNativeWidgetDestroyed();
  }
  if (delete_this) {
    delete this;
  }
}

void NativeWidgetIOS::MoveToPreferredScene(const char* why) {
  if (!window_) {
    return;
  }
  UIWindowScene* preferred = PreferredWindowScene();
  if (preferred) {
    const bool scene_changed = window_.windowScene != preferred;
    if (scene_changed) {
      window_.windowScene = preferred;
    }
    // Top-level windows fill a large (external) screen, like a maximized
    // desktop window. Child bubbles keep their own bounds. The screen can
    // also change size while its scene stays connected (an AirPlay receiver
    // renegotiating its mode, a TV switching resolution), so refit whenever
    // the size differs.
    const bool fills_screen = type_ == Widget::InitParams::TYPE_WINDOW &&
                              !parent_ && FillsDesktop(preferred);
    const gfx::Rect screen_rect = DesktopRect(preferred);
    if (fills_screen && (scene_changed || bounds_ != screen_rect)) {
      // SetBounds also resizes RootView (OnNativeWidgetSizeChanged), so
      // BrowserView lays out at the new screen size.
      SetBounds(screen_rect);
    } else {
      // Same bounds: possibly a new screen scale (3x panel -> 1x TVOut) or
      // a switch between the panel's viewport and a plain frame.
      SyncWindowFrame();
    }
  }
  if (visible_) {
    OrderWindowFront();
    if (compositor_) {
      compositor_->ScheduleDraw();
    }
  }
}

void NativeWidgetIOS::Show(ui::mojom::WindowShowState show_state,
                           const gfx::Rect& restore_bounds) {
  visible_ = true;
  active_ = true;
  if (window_) {
    MoveToPreferredScene("Show");
  }
  if (root_layer_) {
    root_layer_->SetVisible(true);
  }
  if (compositor_) {
    compositor_->SetVisible(true);
    compositor_->ScheduleDraw();
    // The GPU presenter attaches the compositor CALayer asynchronously on
    // the main queue; the first ScheduleDraw can run before that attach.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<NativeWidgetIOS> self) {
                         if (self && self->compositor_) {
                           self->compositor_->ScheduleDraw();
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
  if (window_ && !OnPhoneDesktop()) {
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
  // As NativeWidgetMac/Aura: lay out on the next compositor frame, in
  // UpdateVisualState(). Invalidating the RootView here did nothing (the
  // Widget calls this because the RootView is already invalid), so deferred
  // layouts only ran when something else forced one: a new tab stayed at its
  // zero-width insertion size until the user switched tabs.
  if (compositor_) {
    compositor_->ScheduleDraw();
  }
}

void NativeWidgetIOS::UpdateVisualState() {
  if (delegate_) {
    delegate_->LayoutRootViewIfNecessary();
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
  // MenuHost and other Views callers dereference this unconditionally.
  static base::NoDestructor<ui::GestureRecognizerImplMac> recognizer;
  return recognizer.get();
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
  // Like Mac/Aura, any view hosted inside a widget (e.g. the WebContents
  // UIScrollView under NativeViewHost) maps to that widget.
  for (UIView* view = native_view.Get(); view; view = view.superview) {
    if (NativeWidgetIOS* widget =
            NativeWidgetIOS::GetFromNativeView(gfx::NativeView(view))) {
      return widget;
    }
  }
  return nullptr;
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
  // Includes the widget for |native_view| itself (see widget.h).
  Widget::Widgets widgets = GetAllOwnedWidgets(native_view);
  if (auto* native = NativeWidgetIOS::GetFromNativeView(native_view)) {
    if (Widget* widget = native->GetWidget()) {
      widgets.insert(widget);
    }
  }
  return widgets;
}

Widget::Widgets NativeWidgetPrivate::GetAllOwnedWidgets(
    gfx::NativeView native_view) {
  // Widgets transitively owned by |native_view|'s widget, excluding itself.
  // Returning the widget itself here makes
  // BrowserView::GetAccessibleWindowTitle recurse forever.
  Widget::Widgets widgets;
  NativeWidgetIOS* owner = NativeWidgetIOS::GetFromNativeView(native_view);
  if (!owner) {
    return widgets;
  }
  for (const auto& entry : ViewMap()) {
    NativeWidgetIOS* candidate = entry.second;
    // Skip the owner and native widgets that are closing or whose Widget is
    // gone (delegate_ cleared by ClientDestroyedWidget()).
    if (candidate == owner || candidate->is_closing() || !candidate->GetWidget()) {
      continue;
    }
    for (NativeWidgetIOS* p = candidate->parent_native_widget(); p;
         p = p->parent_native_widget()) {
      if (p == owner) {
        if (Widget* widget = candidate->GetWidget()) {
          widgets.insert(widget);
        }
        break;
      }
    }
  }
  return widgets;
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

////////////////////////////////////////////////////////////////////////////////
// Widget:

// static
void Widget::CloseAllWidgets() {
  // Snapshot the windows first: closing a widget removes it from the map, and
  // may close its children too, so look each one up again before closing.
  std::vector<UIWindow*> windows;
  for (const auto& entry : WindowMap()) {
    windows.push_back(entry.first);
  }
  for (UIWindow* window : windows) {
    NativeWidgetIOS* native = NativeWidgetIOS::GetFromNativeWindow(
        gfx::NativeWindow(window));
    if (!native) {
      continue;
    }
    if (Widget* widget = native->GetWidget()) {
      widget->CloseNow();
    }
  }
}

}  // namespace views
