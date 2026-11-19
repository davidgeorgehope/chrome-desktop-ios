// Copyright 2017 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef UI_ACCELERATED_WIDGET_MAC_CA_LAYER_FRAME_SINK_H_
#define UI_ACCELERATED_WIDGET_MAC_CA_LAYER_FRAME_SINK_H_

#include "build/build_config.h"
#include "ui/accelerated_widget_mac/accelerated_widget_mac_export.h"
#include "ui/gfx/ca_layer_params.h"
#include "ui/gfx/native_ui_types.h"

#if defined(__OBJC__)
@class CALayer;
#endif

namespace ui {

// An interface to an NSView that will embed content described by CALayerParams
// in its hierarchy.
class ACCELERATED_WIDGET_MAC_EXPORT CALayerFrameSink {
 public:
  virtual ~CALayerFrameSink() = default;

  // Translate from a gfx::AcceleratedWidget to the gfx::CALayerFrameSink
  // interface through which frames may be submitted. This may return nullptr.
  static CALayerFrameSink* FromAcceleratedWidget(gfx::AcceleratedWidget widget);

  // Update the embedder's CALayer tree to show the content described by
  // |ca_layer_params|.
  virtual void UpdateCALayerTree(gfx::CALayerParams ca_layer_params) = 0;
};

// Register a CALayerFrameSink that is not backed by CALayerFrameSinkProvider
// (a BELayerHierarchyHostingView on iOS). Views' UIView host uses this so
// Simulator display of DisplayCALayerTree is not swallowed by BrowserEngineKit.
// The returned handle is unique from CALayerFrameSinkProvider viewHandles.
ACCELERATED_WIDGET_MAC_EXPORT gfx::AcceleratedWidget
RegisterUnownedCALayerFrameSink(CALayerFrameSink* sink);
ACCELERATED_WIDGET_MAC_EXPORT void UnregisterUnownedCALayerFrameSink(
    gfx::AcceleratedWidget widget);

#if defined(__OBJC__)
// The iOS ImageTransportSurface presenter looks up a CALayerFrameSinkProvider
// by handle so it can attach the compositor CALayer tree (or a BELayer
// hierarchy handle). Views hosts a plain UIView, so also allow registering
// that view's layer under the same accelerated-widget handle.
ACCELERATED_WIDGET_MAC_EXPORT void RegisterUnownedHostCALayer(
    gfx::AcceleratedWidget widget,
    CALayer* layer);
ACCELERATED_WIDGET_MAC_EXPORT CALayer* LookupUnownedHostCALayer(
    gfx::AcceleratedWidget widget);
#endif  // defined(__OBJC__)

}  // namespace ui

#endif  // UI_ACCELERATED_WIDGET_MAC_CA_LAYER_FRAME_SINK_H_
