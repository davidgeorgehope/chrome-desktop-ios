// Copyright 2017 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ui/accelerated_widget_mac/ca_layer_frame_sink.h"

#include <map>

#include "build/build_config.h"

#if BUILDFLAG(IS_MAC)
#include "ui/accelerated_widget_mac/accelerated_widget_mac.h"
#else
#import <UIKit/UIKit.h>
#include "ui/accelerated_widget_mac/ca_layer_frame_sink_provider.h"
#endif

namespace ui {
namespace {

#if !BUILDFLAG(IS_MAC)
// High bit so these handles never collide with CALayerFrameSinkProvider's
// incrementing sequence (which starts at 1).
constexpr gfx::AcceleratedWidget kUnownedHandleBase = 1ull << 40;

std::map<gfx::AcceleratedWidget, CALayerFrameSink*>& UnownedSinkMap() {
  static auto* map = new std::map<gfx::AcceleratedWidget, CALayerFrameSink*>();
  return *map;
}

std::map<gfx::AcceleratedWidget, CALayer*>& UnownedLayerMap() {
  static auto* map = new std::map<gfx::AcceleratedWidget, CALayer*>();
  return *map;
}
#endif

}  // namespace

#if !BUILDFLAG(IS_MAC)
gfx::AcceleratedWidget RegisterUnownedCALayerFrameSink(CALayerFrameSink* sink) {
  static uint64_t last = 0;
  gfx::AcceleratedWidget handle = kUnownedHandleBase | (++last);
  UnownedSinkMap()[handle] = sink;
  return handle;
}

void UnregisterUnownedCALayerFrameSink(gfx::AcceleratedWidget widget) {
  UnownedSinkMap().erase(widget);
  UnownedLayerMap().erase(widget);
}

void RegisterUnownedHostCALayer(gfx::AcceleratedWidget widget, CALayer* layer) {
  if (!widget) {
    return;
  }
  if (layer) {
    UnownedLayerMap()[widget] = layer;
  } else {
    UnownedLayerMap().erase(widget);
  }
}

CALayer* LookupUnownedHostCALayer(gfx::AcceleratedWidget widget) {
  auto found = UnownedLayerMap().find(widget);
  return found == UnownedLayerMap().end() ? nil : found->second;
}
#else
gfx::AcceleratedWidget RegisterUnownedCALayerFrameSink(CALayerFrameSink* sink) {
  return gfx::kNullAcceleratedWidget;
}

void UnregisterUnownedCALayerFrameSink(gfx::AcceleratedWidget widget) {}

void RegisterUnownedHostCALayer(gfx::AcceleratedWidget widget, CALayer* layer) {
}

CALayer* LookupUnownedHostCALayer(gfx::AcceleratedWidget widget) {
  return nil;
}
#endif

// static
CALayerFrameSink* CALayerFrameSink::FromAcceleratedWidget(
    gfx::AcceleratedWidget widget) {
#if BUILDFLAG(IS_MAC)
  return AcceleratedWidgetMac::Get(widget);
#else
  auto found = UnownedSinkMap().find(widget);
  if (found != UnownedSinkMap().end()) {
    return found->second;
  }
  if (auto* provider = [CALayerFrameSinkProvider lookupByHandle:widget]) {
    return [provider frameSink];
  }
  return nullptr;
#endif
}

}  // namespace ui
