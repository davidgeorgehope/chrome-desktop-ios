// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/platform_util.h"

#import <UIKit/UIKit.h>

#include "base/files/file_path.h"
#include "base/notimplemented.h"
#include "chrome/browser/platform_util_internal.h"
#include "net/base/apple/url_conversions.h"
#include "ui/gfx/native_ui_util.h"
#include "ui/views/widget/widget.h"
#include "url/gurl.h"

// platform_util for iOS desktop Views. The app is sandboxed with no Finder or
// default-app hand-off, so file operations are no-ops; window queries go
// through views::Widget first, then UIKit.

namespace platform_util {

void ShowItemInFolder(Profile* profile, const base::FilePath& full_path) {
  NOTIMPLEMENTED_LOG_ONCE();
}

namespace internal {

void PlatformOpenVerifiedItem(const base::FilePath& path, OpenItemType type) {
  NOTIMPLEMENTED_LOG_ONCE();
}

}  // namespace internal

void OpenExternal(const GURL& url) {
  NSURL* ns_url = net::NSURLWithGURL(url);
  if (!ns_url) {
    return;
  }
  [UIApplication.sharedApplication openURL:ns_url
                                   options:@{}
                         completionHandler:nil];
}

gfx::NativeWindow GetTopLevel(gfx::NativeView view) {
  UIView* ui_view = view.Get();
  return gfx::NativeWindow(ui_view ? ui_view.window : nil);
}

gfx::NativeView GetViewForWindow(gfx::NativeWindow native_window) {
  return gfx::GetViewForWindow(native_window);
}

gfx::NativeView GetParent(gfx::NativeView view) {
  return gfx::NativeView(nil);
}

bool IsWindowActive(gfx::NativeWindow native_window) {
  if (views::Widget* widget =
          views::Widget::GetWidgetForNativeWindow(native_window)) {
    return widget->IsActive();
  }
  UIWindow* window = native_window.Get();
  return window && window.isKeyWindow;
}

void ActivateWindow(gfx::NativeWindow native_window) {
  if (views::Widget* widget =
          views::Widget::GetWidgetForNativeWindow(native_window)) {
    widget->Activate();
    return;
  }
  [native_window.Get() makeKeyAndVisible];
}

bool IsVisible(gfx::NativeView native_view) {
  if (views::Widget* widget =
          views::Widget::GetWidgetForNativeView(native_view)) {
    return widget->IsVisible();
  }
  UIView* view = native_view.Get();
  return view && !view.hidden && view.window && !view.window.hidden;
}

}  // namespace platform_util
