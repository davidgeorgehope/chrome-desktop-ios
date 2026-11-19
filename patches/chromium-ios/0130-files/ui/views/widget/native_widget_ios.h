// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef UI_VIEWS_WIDGET_NATIVE_WIDGET_IOS_H_
#define UI_VIEWS_WIDGET_NATIVE_WIDGET_IOS_H_

#include <map>
#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "components/viz/common/surfaces/parent_local_surface_id_allocator.h"
#include "ui/base/ime/ime_key_event_dispatcher.h"
#include "ui/gfx/geometry/size.h"
#include "ui/compositor/layer_delegate.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/native_ui_types.h"
#include "ui/views/focus/focus_manager.h"
#include "ui/views/views_export.h"
#include "ui/views/widget/native_widget_private.h"
#include "ui/views/widget/widget.h"

#ifdef __OBJC__
@class UIView;
@class UIWindow;
#else
class UIView;
class UIWindow;
#endif

namespace ui {
class Compositor;
class GestureRecognizer;
class InputMethod;
class KeyEvent;
class Layer;
class MouseEvent;
}  // namespace ui

namespace views {

class TooltipManager;

// In-process Views NativeWidget for iOS. Hosts a UIWindow / UIView and a
// ui::Compositor whose output is composited into a CALayer via
// CALayerFrameSinkProvider + DisplayCALayerTree (Simulator). This is the
// Mac-style (no Aura) path for enable_ios_desktop_views.
class VIEWS_EXPORT NativeWidgetIOS : public internal::NativeWidgetPrivate,
                                     public ui::LayerDelegate,
                                     public ui::ImeKeyEventDispatcher,
                                     public FocusChangeListener {
 public:
  explicit NativeWidgetIOS(internal::NativeWidgetDelegate* delegate);
  NativeWidgetIOS(const NativeWidgetIOS&) = delete;
  NativeWidgetIOS& operator=(const NativeWidgetIOS&) = delete;
  ~NativeWidgetIOS() override;

  static NativeWidgetIOS* GetFromNativeView(gfx::NativeView view);

  // Input entry points for the iOS desktop Views host's phone trackpad:
  // deliver a synthetic event to the widget that owns |window|. Locations are
  // in that window's DIPs. Returns false when |window| is not a widget.
  static bool DispatchTrackpadMouseEvent(gfx::NativeWindow window,
                                         ui::MouseEvent* event);
  static bool DispatchTrackpadKeyEvent(gfx::NativeWindow window,
                                       ui::KeyEvent* event);
  static NativeWidgetIOS* GetFromNativeWindow(gfx::NativeWindow window);

  // Sees trackpad key events before any widget (MenuPreTargetHandlerIOS uses
  // it the way MenuPreTargetHandlerMac uses NativeWidgetMacEventMonitor).
  class KeyEventMonitor {
   public:
    // Returns true when the event was consumed.
    virtual bool OnTrackpadKeyEvent(ui::KeyEvent* event) = 0;

   protected:
    virtual ~KeyEventMonitor() = default;
  };
  static void AddKeyEventMonitor(KeyEventMonitor* monitor);
  static void RemoveKeyEventMonitor(KeyEventMonitor* monitor);
  static bool HasKeyEventMonitor();

  // UIWindow of the widget holding mouse capture (e.g. an open menu), or null.
  // The trackpad sends all pointer events there while it is set.
  static gfx::NativeWindow GetCaptureWindow();

  // Moves this widget's UIWindow onto the preferred UIWindowScene (the
  // external display when connected). Widgets can be created before UIKit
  // connects any scene; this re-homes them once one connects.
  void MoveToPreferredScene(const char* why);

  // internal::NativeWidgetPrivate:
  void InitNativeWidget(Widget::InitParams params) override;
  void OnWidgetInitDone() override;
  void ReparentNativeViewImpl(gfx::NativeView new_parent) override;
  std::unique_ptr<FrameView> CreateFrameView() override;
  bool ShouldUseNativeFrame() const override;
  bool ShouldWindowContentsBeTransparent() const override;
  void FrameTypeChanged() override;
  Widget* GetWidget() override;
  const Widget* GetWidget() const override;
  gfx::NativeView GetNativeView() const override;
  gfx::NativeWindow GetNativeWindow() const override;
  Widget* GetTopLevelWidget() override;
  const ui::Compositor* GetCompositor() const override;
  const ui::Layer* GetLayer() const override;
  void ReorderNativeViews() override;
  void ViewRemoved(View* view) override;
  void SetNativeWindowProperty(const char* name, void* value) override;
  void* GetNativeWindowProperty(const char* name) const override;
  TooltipManager* GetTooltipManager() const override;
  void SetCapture() override;
  void ReleaseCapture() override;
  bool HasCapture() const override;
  ui::InputMethod* GetInputMethod() override;
  void CenterWindow(const gfx::Size& size) override;
  void GetWindowPlacement(gfx::Rect* bounds,
                          ui::mojom::WindowShowState* show_state) const override;
  bool SetWindowTitle(const std::u16string& title) override;
  void SetWindowIcons(const gfx::ImageSkia& window_icon,
                      const gfx::ImageSkia& app_icon) override;
  void InitModalType(ui::mojom::ModalType modal_type) override;
  void SetBackgroundColor(SkColor background_color) override;
  gfx::Rect GetWindowBoundsInScreen() const override;
  gfx::Rect GetClientAreaBoundsInScreen() const override;
  gfx::Rect GetRestoredBounds() const override;
  std::string GetWorkspace() const override;
  void SetBounds(const gfx::Rect& bounds) override;
  void SetBoundsConstrained(const gfx::Rect& bounds) override;
  void SetSize(const gfx::Size& size) override;
  void StackAbove(gfx::NativeView native_view) override;
  void StackAtTop() override;
  bool IsStackedAbove(gfx::NativeView native_view) override;
  void SetShape(std::unique_ptr<Widget::ShapeRects> shape) override;
  void Close() override;
  void CloseNow() override;
  void Show(ui::mojom::WindowShowState show_state,
            const gfx::Rect& restore_bounds) override;
  void Hide() override;
  bool IsVisible() const override;
  bool IsVisibleOnScreen() const override;
  void Activate() override;
  void Deactivate() override;
  bool IsActive() const override;
  void SetZOrderLevel(ui::ZOrderLevel order) override;
  ui::ZOrderLevel GetZOrderLevel() const override;
  void SetVisibleOnAllWorkspaces(bool always_visible) override;
  bool IsVisibleOnAllWorkspaces() const override;
  void Maximize() override;
  void Minimize() override;
  bool IsMaximized() const override;
  bool IsMinimized() const override;
  void Restore() override;
  void SetFullscreen(bool fullscreen, int64_t target_display_id) override;
  bool IsFullscreen() const override;
  void SetCanAppearInExistingFullscreenSpaces(
      bool can_appear_in_existing_fullscreen_spaces) override;
  void SetOpacity(float opacity) override;
  void SetAspectRatio(const gfx::SizeF& aspect_ratio,
                      const gfx::Size& excluded_margin) override;
  void FlashFrame(bool flash) override;
  void RunDragDropLoop(std::unique_ptr<ui::OSExchangeData> data,
                       const gfx::Point& location,
                       int operation,
                       ui::mojom::DragEventSource source) override;
  void CancelDragDropLoop(View* view) override;
  void SchedulePaintInRect(const gfx::Rect& rect) override;
  void ScheduleLayout() override;
  void SetCursor(const ui::Cursor& cursor) override;
  bool IsMouseEventsEnabled() const override;
  bool IsMouseButtonDown() const override;
  void ClearNativeFocus() override;
  gfx::Rect GetWorkAreaBoundsInScreen() const override;
  Widget::MoveLoopResult RunMoveLoop(
      const gfx::Vector2d& drag_offset,
      Widget::MoveLoopSource source,
      Widget::MoveLoopEscapeBehavior escape_behavior) override;
  void EndMoveLoop() override;
  void SetVisibilityChangedAnimationsEnabled(bool value) override;
  void SetVisibilityAnimationDuration(const base::TimeDelta& duration) override;
  void SetVisibilityAnimationTransition(
      Widget::VisibilityTransition transition) override;
  ui::GestureRecognizer* GetGestureRecognizer() override;
  ui::GestureConsumer* GetGestureConsumer() override;
  void OnSizeConstraintsChanged() override;
  void OnNativeViewHierarchyWillChange() override;
  void OnNativeViewHierarchyChanged() override;
  bool SetAllowScreenshots(bool allow) override;
  bool AreScreenshotsAllowed() override;
  bool IsDesktopNativeWidget() const override;
  std::string GetName() const override;
  base::WeakPtr<NativeWidgetPrivate> GetWeakPtr() override;

  // ui::LayerDelegate:
  void OnPaintLayer(const ui::PaintContext& context) override;
  void OnDeviceScaleFactorChanged(float old_device_scale_factor,
                                  float new_device_scale_factor) override;

  // ui::ImeKeyEventDispatcher:
  ui::EventDispatchDetails DispatchKeyEventPostIME(ui::KeyEvent* key) override;

  // FocusChangeListener:
  void OnWillChangeFocus(View* focused_before, View* focused_now) override {}
  void OnDidChangeFocus(View* focused_before, View* focused_now) override;

 private:
  void CreateCompositor(const Widget::InitParams& params);
  void SyncWindowFrame();
  void DestroyCompositor();
  void UpdateCompositorSurface();

  raw_ptr<internal::NativeWidgetDelegate> delegate_ = nullptr;
  std::unique_ptr<internal::NativeWidgetDelegate> owned_delegate_;
  Widget::InitParams::Ownership ownership_ =
      Widget::InitParams::NATIVE_WIDGET_OWNS_WIDGET;
  std::string name_;
  Widget::InitParams::Type type_ = Widget::InitParams::TYPE_WINDOW;
  // Owning widget (InitParams::parent or ReparentNativeView). Each iOS widget
  // has its own UIWindow, so ownership is tracked here rather than through the
  // UIView hierarchy. Cleared when the parent is destroyed.
  raw_ptr<NativeWidgetIOS> parent_ = nullptr;
  // FocusManager this widget listens to (see OnDidChangeFocus).
  raw_ptr<FocusManager> observed_focus_manager_ = nullptr;
  bool destroying_notified_ = false;
  void StopObservingFocus();

 public:
  NativeWidgetIOS* parent_native_widget() const { return parent_; }

 private:

  UIWindow* __strong window_ = nil;
  UIView* __strong content_view_ = nil;

  std::unique_ptr<ui::Compositor> compositor_;
  std::unique_ptr<ui::Layer> root_layer_;
  std::unique_ptr<TooltipManager> tooltip_manager_;
  std::unique_ptr<ui::InputMethod> input_method_;

  gfx::Rect bounds_;
  viz::ParentLocalSurfaceIdAllocator local_surface_id_allocator_;
  gfx::Size compositor_size_pixels_;
  float compositor_scale_ = 0.f;
  bool visible_ = false;
  bool active_ = false;
  bool closing_ = false;
  bool has_capture_ = false;
  bool screenshots_allowed_ = true;
  ui::ZOrderLevel z_order_ = ui::ZOrderLevel::kNormal;
  std::map<std::string, raw_ptr<void>> native_window_properties_;

  base::WeakPtrFactory<NativeWidgetIOS> weak_factory_{this};
};

}  // namespace views

#endif  // UI_VIEWS_WIDGET_NATIVE_WIDGET_IOS_H_
