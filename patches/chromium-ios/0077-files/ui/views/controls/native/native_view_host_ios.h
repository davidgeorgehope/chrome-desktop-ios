// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef UI_VIEWS_CONTROLS_NATIVE_NATIVE_VIEW_HOST_IOS_H_
#define UI_VIEWS_CONTROLS_NATIVE_NATIVE_VIEW_HOST_IOS_H_

#include <optional>

#include "base/memory/raw_ptr.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/rounded_corners_f.h"
#include "ui/views/controls/native/native_view_host_wrapper.h"
#include "ui/views/views_export.h"

#ifdef __OBJC__
@class UIView;
#else
class UIView;
#endif

namespace views {

class NativeViewHost;

// Hosts a UIView (for example a WebContents view) as a subview of the
// NativeWidgetIOS content view, positioned over the Views layer tree.
class NativeViewHostIOS : public NativeViewHostWrapper {
 public:
  explicit NativeViewHostIOS(NativeViewHost* host);
  NativeViewHostIOS(const NativeViewHostIOS&) = delete;
  NativeViewHostIOS& operator=(const NativeViewHostIOS&) = delete;
  ~NativeViewHostIOS() override;

  // NativeViewHostWrapper:
  void AttachNativeView() override;
  void NativeViewDetaching(bool destroyed) override;
  void AddedToWidget() override;
  void RemovedFromWidget() override;
  bool SetNativeViewCornerRadii(
      const gfx::RoundedCornersF& corner_radii) override;
  gfx::RoundedCornersF GetNativeViewCornerRadii() const override;
  gfx::Rect GetNativeViewClipRect() const override;
  void InstallClip(int x, int y, int w, int h) override;
  bool HasInstalledClip() override;
  void UninstallClip() override;
  bool SetNativeViewClipRect(const gfx::Rect& clip_rect) override;
  void ShowWidget(int x,
                  int y,
                  int w,
                  int h,
                  int native_w,
                  int native_h) override;
  void HideWidget() override;
  void SetFocus() override;
  gfx::NativeView GetNativeViewContainer() const override;
  gfx::NativeViewAccessible GetNativeViewAccessible() override;
  ui::Cursor GetCursor(int x, int y) override;
  void SetVisible(bool visible) override;
  void SetParentAccessible(gfx::NativeViewAccessible) override;
  gfx::NativeViewAccessible GetParentAccessible() override;
  ui::Layer* GetUILayer() override;

 private:
  UIView* GetHostingView() const;
  void ApplyCornerRadii();

  raw_ptr<NativeViewHost> host_;
  UIView* __strong native_view_;
  std::optional<gfx::Rect> clip_rect_;
  gfx::RoundedCornersF corner_radii_;
  gfx::NativeViewAccessible parent_accessible_;
};

}  // namespace views

#endif  // UI_VIEWS_CONTROLS_NATIVE_NATIVE_VIEW_HOST_IOS_H_
