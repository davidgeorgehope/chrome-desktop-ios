// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ui/views/controls/native/native_view_host_ios.h"

#import <UIKit/UIKit.h>

#include <algorithm>
#include <memory>

#include "base/check.h"
#include "ui/views/controls/native/native_view_host.h"
#include "ui/views/widget/widget.h"

namespace views {

NativeViewHostIOS::NativeViewHostIOS(NativeViewHost* host) : host_(host) {}

NativeViewHostIOS::~NativeViewHostIOS() {
  [native_view_ removeFromSuperview];
  native_view_ = nil;
}

UIView* NativeViewHostIOS::GetHostingView() const {
  Widget* widget = host_->GetWidget();
  if (!widget) {
    return nil;
  }
  return widget->GetNativeView().Get();
}

void NativeViewHostIOS::AttachNativeView() {
  CHECK(host_->native_view());
  native_view_ = host_->native_view().Get();
  UIView* hosting_view = GetHostingView();
  if (native_view_ && hosting_view && native_view_.superview != hosting_view) {
    [native_view_ removeFromSuperview];
    [hosting_view addSubview:native_view_];
  }
  native_view_.hidden = YES;
  ApplyCornerRadii();
}

void NativeViewHostIOS::NativeViewDetaching(bool destroyed) {
  if (!destroyed) {
    native_view_.hidden = YES;
    [native_view_ removeFromSuperview];
  }
  native_view_ = nil;
}

void NativeViewHostIOS::AddedToWidget() {
  if (!host_->native_view()) {
    return;
  }
  AttachNativeView();
  host_->InvalidateLayout();
}

void NativeViewHostIOS::RemovedFromWidget() {
  if (!host_->native_view()) {
    return;
  }
  NativeViewDetaching(false);
}

bool NativeViewHostIOS::SetNativeViewCornerRadii(
    const gfx::RoundedCornersF& corner_radii) {
  corner_radii_ = corner_radii;
  ApplyCornerRadii();
  return true;
}

gfx::RoundedCornersF NativeViewHostIOS::GetNativeViewCornerRadii() const {
  return corner_radii_;
}

void NativeViewHostIOS::ApplyCornerRadii() {
  if (!native_view_) {
    return;
  }
  // CALayer supports a single radius; use the largest requested corner.
  float radius = std::max({corner_radii_.upper_left(),
                           corner_radii_.upper_right(),
                           corner_radii_.lower_right(),
                           corner_radii_.lower_left()});
  native_view_.layer.cornerRadius = radius;
  native_view_.layer.masksToBounds = radius > 0 || clip_rect_.has_value();
}

gfx::Rect NativeViewHostIOS::GetNativeViewClipRect() const {
  return clip_rect_.value_or(gfx::Rect());
}

void NativeViewHostIOS::InstallClip(int x, int y, int w, int h) {
  clip_rect_ = gfx::Rect(x, y, w, h);
}

bool NativeViewHostIOS::HasInstalledClip() {
  return clip_rect_.has_value();
}

void NativeViewHostIOS::UninstallClip() {
  clip_rect_.reset();
}

bool NativeViewHostIOS::SetNativeViewClipRect(const gfx::Rect& clip_rect) {
  clip_rect_ = clip_rect;
  return true;
}

void NativeViewHostIOS::ShowWidget(int x,
                                   int y,
                                   int w,
                                   int h,
                                   int native_w,
                                   int native_h) {
  if (!native_view_) {
    return;
  }
  // Views and UIKit both use DIPs (points) with a top-left origin.
  gfx::Rect frame(x, y, w, h);
  if (clip_rect_) {
    frame.Intersect(*clip_rect_);
  }
  native_view_.frame = frame.ToCGRect();
  native_view_.hidden = NO;
  ApplyCornerRadii();
  static int logs = 0;
  static gfx::Rect last_frame;
  if (logs < 40 && frame != last_frame) {
    logs++;
    last_frame = frame;
    NSLog(@"[DeskBrowser] NativeViewHost ShowWidget %s view=%@ super=%@ "
          @"index=%lu/%lu",
          frame.ToString().c_str(), NSStringFromClass([native_view_ class]),
          NSStringFromClass([native_view_.superview class]),
          (unsigned long)[native_view_.superview.subviews
              indexOfObject:native_view_],
          (unsigned long)native_view_.superview.subviews.count);
  }
}

void NativeViewHostIOS::HideWidget() {
  native_view_.hidden = YES;
}

void NativeViewHostIOS::SetFocus() {
  if ([native_view_ canBecomeFirstResponder]) {
    [native_view_ becomeFirstResponder];
  }
}

gfx::NativeView NativeViewHostIOS::GetNativeViewContainer() const {
  return gfx::NativeView(native_view_);
}

gfx::NativeViewAccessible NativeViewHostIOS::GetNativeViewAccessible() {
  return gfx::NativeViewAccessible();
}

ui::Cursor NativeViewHostIOS::GetCursor(int x, int y) {
  return ui::Cursor();
}

void NativeViewHostIOS::SetVisible(bool visible) {
  native_view_.hidden = !visible;
}

void NativeViewHostIOS::SetParentAccessible(
    gfx::NativeViewAccessible accessible) {
  parent_accessible_ = accessible;
}

gfx::NativeViewAccessible NativeViewHostIOS::GetParentAccessible() {
  return parent_accessible_;
}

ui::Layer* NativeViewHostIOS::GetUILayer() {
  return nullptr;
}

// static
NativeViewHostWrapper* NativeViewHostWrapper::CreateWrapper(
    NativeViewHost* host) {
  return new NativeViewHostIOS(host);
}

}  // namespace views
