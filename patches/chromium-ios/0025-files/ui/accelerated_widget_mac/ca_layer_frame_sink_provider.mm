// Copyright 2024 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ui/accelerated_widget_mac/ca_layer_frame_sink_provider.h"

#if !BUILDFLAG(IS_IOS_TVOS)
#import <BrowserEngineKit/BELayerHierarchyHostingTransactionCoordinator.h>
#endif

#include <map>

namespace {

std::map<gfx::AcceleratedWidget, CALayerFrameSinkProvider*>&
WidgetToSinkProviderMap() {
  static std::map<gfx::AcceleratedWidget, CALayerFrameSinkProvider*> map;
  return map;
}

}  // namespace

@implementation CALayerFrameSinkProvider {
  uint64_t _view_handle;
}

- (ui::CALayerFrameSink*)frameSink {
  return nil;
}

- (gfx::AcceleratedWidget)viewHandle {
  return _view_handle;
}

- (void)registerViewHandleIfNeeded {
  if (_view_handle) {
    return;
  }
  static uint64_t last_sequence_number = 0;
  _view_handle = ++last_sequence_number;
  WidgetToSinkProviderMap().insert(std::make_pair(_view_handle, self));
}

- (id)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    [self registerViewHandleIfNeeded];
  }
  return self;
}

- (id)init {
  return [self initWithFrame:CGRectZero];
}

- (void)dealloc {
  if (_view_handle) {
    WidgetToSinkProviderMap().erase(_view_handle);
  }
}

+ (CALayerFrameSinkProvider*)lookupByHandle:(uint64_t)viewHandle {
  auto found = WidgetToSinkProviderMap().find(viewHandle);
  if (found == WidgetToSinkProviderMap().end()) {
    return nullptr;
  }
  return found->second;
}

- (void)deskBrowserRebindLayerHierarchyAfterMovingWindows {
#if !BUILDFLAG(IS_IOS_TVOS)
  if (!self.window) {
    return;
  }
  BELayerHierarchyHandle* handle = self.handle;
  if (!handle) {
    return;
  }
  // Drop and re-assign the handle once the view is in the new window
  // so BrowserEngineKit re-attaches the remote layer tree.
  self.handle = nil;
  [self layoutIfNeeded];
  NSError* error = nil;
  BELayerHierarchyHostingTransactionCoordinator* coordinator =
      [BELayerHierarchyHostingTransactionCoordinator coordinatorWithError:&error];
  if (coordinator) {
    [coordinator addLayerHierarchyHostingView:self];
    self.handle = handle;
    [coordinator commit];
  } else {
    self.handle = handle;
  }
#endif  // !BUILDFLAG(IS_IOS_TVOS)
}
@end
