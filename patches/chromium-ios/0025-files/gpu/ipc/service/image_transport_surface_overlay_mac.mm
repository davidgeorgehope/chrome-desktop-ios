// Copyright 2015 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "gpu/ipc/service/image_transport_surface_overlay_mac.h"

#include <dawn/native/MetalBackend.h>
#include <dawn/webgpu_cpp.h>

#include <memory>
#include <sstream>
#include <utility>
#include <variant>

#include "base/command_line.h"
#include "base/logging.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/metrics/histogram_macros.h"
#include "base/rand_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "base/trace_event/trace_event.h"
#include "components/viz/common/features.h"
#include "gpu/command_buffer/common/swap_buffers_complete_params.h"
#include "gpu/config/gpu_finch_features.h"
#include "gpu/ipc/service/gpu_channel_manager.h"
#include "gpu/ipc/service/gpu_channel_manager_delegate.h"
#include "ui/accelerated_widget_mac/ca_layer_tree_coordinator.h"
#include "ui/accelerated_widget_mac/ca_renderer_layer_tree.h"
#include "ui/gfx/geometry/rect_conversions.h"
#include "ui/gfx/gpu_fence.h"
#include "ui/gfx/overlay_plane_data.h"
#include "ui/gl/ca_renderer_layer_params.h"

#if BUILDFLAG(IS_IOS) && !BUILDFLAG(IS_IOS_TVOS)
#include "gpu/ipc/common/ios/be_layer_hierarchy_transport.h"
#include "ui/accelerated_widget_mac/ca_layer_frame_sink.h"
#include "ui/accelerated_widget_mac/ca_layer_frame_sink_provider.h"
#endif

#if BUILDFLAG(SKIA_USE_DAWN)
#include "gpu/command_buffer/service/dawn_context_provider.h"
#endif

// From ANGLE's EGL/eglext_angle.h. This should be included instead of being
// redefined here.
#ifndef EGL_ANGLE_device_metal
#define EGL_ANGLE_device_metal 1
#define EGL_METAL_DEVICE_ANGLE 0x34A6
#endif /* EGL_ANGLE_device_metal */

namespace gpu {

namespace {
constexpr base::TimeDelta kHistogramMinTime = base::Microseconds(5);
constexpr base::TimeDelta kHistogramMaxTime = base::Milliseconds(16);
constexpr int kHistogramTimeBuckets = 50;

// Control use of AVFoundation to draw video content.
BASE_FEATURE(kAVFoundationOverlays,
             "avfoundation-overlays",
             base::FEATURE_ENABLED_BY_DEFAULT);

#if BUILDFLAG(IS_MAC)
// Record the delay from the system CVDisplayLink or CADisplaylink source to
// CrGpuMain OnVSyncPresentation().
void RecordVSyncCallbackDelay(base::TimeDelta delay) {
  UMA_HISTOGRAM_CUSTOM_MICROSECONDS_TIMES(
      "GPU.Presentation.VSyncCallbackDelay", delay,
      /*min=*/base::Microseconds(10),
      /*max=*/base::Milliseconds(33), /*bucket_count=*/50);
}
#endif  // BUILDFLAG(IS_MAC)

id<MTLDevice> GetMTLDevice(scoped_refptr<SharedContextState> context_state) {
#if BUILDFLAG(SKIA_USE_DAWN)
  if (context_state->IsGraphiteDawnMetal()) {
    CHECK(context_state->dawn_context_provider());
    return dawn::native::metal::GetMTLDevice(
        context_state->dawn_context_provider()->GetDevice().Get());
  }
#endif
  if (context_state->GrContextIsGL()) {
    EGLAttrib angle_device_attrib = 0;
    if (eglQueryDisplayAttribEXT(context_state->display()->GetDisplay(),
                                 EGL_DEVICE_EXT, &angle_device_attrib)) {
      EGLDeviceEXT angle_device =
          reinterpret_cast<EGLDeviceEXT>(angle_device_attrib);
      EGLAttrib metal_device_attrib = 0;
      if (eglQueryDeviceAttribEXT(angle_device, EGL_METAL_DEVICE_ANGLE,
                                  &metal_device_attrib)) {
        return (__bridge id)(void*)metal_device_attrib;
      }
    }
  }
  return nil;
}

void BufferPresented(base::WeakPtr<gpu::ImageTransportSurfaceOverlayMacEGL>
                         image_transfer_weak_ptr,
                     gl::GLSurface::PresentationCallback callback,
                     const gfx::PresentationFeedback& feedback) {
  if (!image_transfer_weak_ptr) {
    return;
  }

  DCHECK(!callback.is_null());
  std::move(callback).Run(feedback);
}

}  // namespace

ImageTransportSurfaceOverlayMacEGL::ImageTransportSurfaceOverlayMacEGL(
    scoped_refptr<SharedContextState> context_state,
    SurfaceHandle surface_handle)
    : weak_ptr_factory_(this) {
  static bool av_disabled_at_command_line =
      !base::FeatureList::IsEnabled(kAVFoundationOverlays);

  auto buffer_presented_callback =
      base::BindRepeating(&BufferPresented, weak_ptr_factory_.GetWeakPtr());

  auto gl_make_current_callback =
      base::BindRepeating(&SharedContextState::MakeCurrent, context_state,
                          /*surface=*/nullptr, /*needs_gl=*/true);

  ca_layer_tree_coordinator_ = std::make_unique<ui::CALayerTreeCoordinator>(
      !av_disabled_at_command_line, std::move(buffer_presented_callback),
      std::move(gl_make_current_callback), GetMTLDevice(context_state));

#if BUILDFLAG(IS_IOS) && !BUILDFLAG(IS_IOS_TVOS)
  // BELayerHierarchy and UIKit host attachment must run on the main queue,
  // but this constructor often runs on the GPU thread while the UI/compositor
  // thread is blocked in SkiaOutputSurfaceImpl::FlushGpuTasksWithImpl.
  // dispatch_sync(main) deadlocks in that case (Views M1: blank widget,
  // CreateLayerTreeFrameSink never returns). Hop with dispatch_async unless
  // we are already on the main thread.
  // Do not capture root_ca_layer() here: EnsureCAContextAndRootLayer is
  // lazy, and a raw pointer taken before the first commit can be stale
  // if we ever recreate the layer. Look it up on the main queue instead.
  const gpu::SurfaceHandle handle = surface_handle;
  __block ImageTransportSurfaceOverlayMacEGL* overlay = this;
  void (^apply_on_main)(void) = ^{
    NSError* error = nullptr;
    overlay->layer_hierarchy_ =
        [BELayerHierarchy layerHierarchyWithError:&error];
    CALayerFrameSinkProvider* sink =
        [CALayerFrameSinkProvider lookupByHandle:handle];
    CALayer* host_layer =
        sink ? sink.layer : ui::LookupUnownedHostCALayer(handle);
    CALayer* root_ca_layer = overlay->ca_layer_tree_coordinator_
                                 ? overlay->ca_layer_tree_coordinator_
                                       ->root_ca_layer()
                                 : nil;
    NSLog(@"[DeskBrowser] presenter host lookup handle=%llu sink=%p "
          @"host_layer=%p host_bounds=%.1fx%.1f be_layer=%d error=%@",
          (unsigned long long)handle, sink, host_layer,
          host_layer ? host_layer.bounds.size.width : 0,
          host_layer ? host_layer.bounds.size.height : 0,
          overlay->layer_hierarchy_ ? 1 : 0, error);
    xpc_object_t ipc_representation = nil;
    if (overlay->layer_hierarchy_ && sink) {
      overlay->layer_hierarchy_.layer = root_ca_layer;
      ipc_representation =
          [overlay->layer_hierarchy_.handle createXPCRepresentation];
      // In-process GPU never forwards the handle (InProcessGpuThread is a
      // no-op). Attach it here whenever the sink lives in this process.
      sink.handle = overlay->layer_hierarchy_.handle;
    } else {
      if (!overlay->layer_hierarchy_) {
        LOG(ERROR) << "BELayerHierarchy creation failed: "
                   << (error ? base::SysNSStringToUTF8(
                                   error.localizedDescription)
                             : std::string("unknown"));
      }
      // Simulator / unsigned host / Views UIView fallback: host the
      // compositor CALayer tree as a sublayer of the platform view.
      if (host_layer && root_ca_layer) {
        // iOS has no CAContext in EnsureCAContextAndRootLayer, so
        // CALayerParams stay empty and never reach DisplayCALayerTree.
        // Parent the compositor layer tree directly on the platform view.
        CGRect bounds = host_layer.bounds;
        if (CGRectIsEmpty(bounds)) {
          bounds = host_layer.superlayer
                       ? host_layer.superlayer.bounds
                       : CGRectMake(0, 0, 370, 260);
        }
        root_ca_layer.frame = bounds;
        root_ca_layer.contentsScale =
            host_layer.contentsScale > 0 ? host_layer.contentsScale : 3;
        if (root_ca_layer.superlayer != host_layer) {
          [root_ca_layer removeFromSuperlayer];
          [host_layer addSublayer:root_ca_layer];
        }
        NSLog(@"[DeskBrowser] attached compositor root CALayer to host "
              @"frame=%.1fx%.1f scale=%.1f be_layer=%d root=%p host=%p "
              @"sublayers=%lu",
              bounds.size.width, bounds.size.height,
              root_ca_layer.contentsScale, overlay->layer_hierarchy_ ? 1 : 0,
              root_ca_layer, host_layer,
              (unsigned long)root_ca_layer.sublayers.count);
      } else {
        NSLog(@"[DeskBrowser] No CALayer host for surface handle %llu "
              @"host=%p root=%p",
              (unsigned long long)handle, host_layer, root_ca_layer);
        LOG(ERROR) << "No CALayer host for surface handle " << handle;
      }
    }
    if (ipc_representation) {
      BELayerHierarchyTransport* transport =
          BELayerHierarchyTransport::GetInstance();
      if (transport) {
        transport->ForwardBELayerHierarchyToBrowser(handle, ipc_representation);
      }
    }
  };
  if ([NSThread isMainThread]) {
    apply_on_main();
  } else {
    dispatch_async(dispatch_get_main_queue(), apply_on_main);
  }
#endif
}

// For testing
ImageTransportSurfaceOverlayMacEGL::ImageTransportSurfaceOverlayMacEGL(
    std::unique_ptr<ui::CALayerTreeCoordinator> ca_layer_tree_coordinator
#if BUILDFLAG(IS_MAC)
    ,
    std::unique_ptr<ui::VSyncCallbackMac> vsync_callback_mac
#endif
    )
    : ca_layer_tree_coordinator_(std::move(ca_layer_tree_coordinator)),
#if BUILDFLAG(IS_MAC)
      vsync_callback_mac_(std::move(vsync_callback_mac)),
#endif
      weak_ptr_factory_(this) {
}

ImageTransportSurfaceOverlayMacEGL::~ImageTransportSurfaceOverlayMacEGL() {
  ca_layer_tree_coordinator_.reset();

#if BUILDFLAG(IS_IOS) && !BUILDFLAG(IS_IOS_TVOS)
  // Capture and retain the BELayerHierarchy in a local __block var before
  // dropping the member var ref. Do this before dispatch_async() to avoid a
  // dealloc race between the block and the member var releasing the last ref.
  __block BELayerHierarchy* layer_hierarchy =
      std::exchange(layer_hierarchy_, nil);
  dispatch_async(dispatch_get_main_queue(), ^{
    [layer_hierarchy invalidate];
    layer_hierarchy = nil;
  });
#endif
}

void ImageTransportSurfaceOverlayMacEGL::Present(
    SwapCompletionCallback completion_callback,
    PresentationCallback presentation_callback,
    gfx::FrameData data) {
  TRACE_EVENT0("gpu", "ImageTransportSurfaceOverlayMac::Present");
  static int presents = 0;
  if (presents < 8) {
    presents++;
    NSLog(@"[DeskBrowser] presenter Present #%d", presents);
  }
  ca_layer_tree_coordinator_->SetCALayerErrorCode(data.ca_layer_error_code);

  // Commit the first pending frame before adding one more in Present() if there
  // are more than supported .
  if (ca_layer_tree_coordinator_->NumPendingSwaps() >= cap_max_pending_swaps_) {
    TRACE_EVENT0("gpu", "Exceeds the max pending swaps. Commit now.");
    CommitPresentedFrameToCA();
  }

  // Set the display HDR headroom to be used for any tone mapping to be done
  // at the CoreAnimation level.
  ca_layer_tree_coordinator_->GetPendingCARendererLayerTree()
      ->SetDisplayHDRHeadroom(data.display_hdr_headroom);

  ca_layer_tree_coordinator_->Present(std::move(completion_callback),
                                      std::move(presentation_callback));

#if BUILDFLAG(IS_MAC)
  if (display_link_mac_ && !vsync_callback_mac_) {
    vsync_callback_mac_ =
        display_link_mac_->RegisterCallback(base::BindRepeating(
            &ImageTransportSurfaceOverlayMacEGL::OnVSyncPresentation,
            weak_ptr_factory_.GetWeakPtr()));
  }

  bool delay_presentation_until_next_vsync =
      features::IsVSyncAligned() ||
      (features::IsVSyncAlignedForScrolling() && data.is_handling_interaction);

  // The current frame has been added to
  // ca_layer_tree_coordinator_->NumPendingSwaps() after calling
  // ca_layer_tree_coordinator_->Present(). Check NumPendingSwaps() > 1 to see
  // whether there is any previous pending frame. The current frame must wait in
  // the queue if there is already one before this.
  if ((features::IsVSyncAligned() || features::IsVSyncAlignedForScrolling()) &&
      ca_layer_tree_coordinator_->NumPendingSwaps() > 1) {
    delay_presentation_until_next_vsync = true;
  }

  if (vsync_callback_mac_) {
    vsync_callback_mac_keep_alive_counter_ = kMaxKeepAliveCounter;
    if (delay_presentation_until_next_vsync) {
      // Delay CommitPresentedFrameToCA() until OnVSyncPresentation().
      return;
    }
  }
#endif

  CommitPresentedFrameToCA();
}

void ImageTransportSurfaceOverlayMacEGL::CommitPresentedFrameToCA() {
  //  Do a GL fence for flush to apply back-pressure before drawing.
  {
    base::TimeTicks start_time = base::TimeTicks::Now();
    ca_layer_tree_coordinator_->ApplyBackpressure();
    UMA_HISTOGRAM_CUSTOM_MICROSECONDS_TIMES(
        "Gpu.Mac.BackpressureUs", base::TimeTicks::Now() - start_time,
        kHistogramMinTime, kHistogramMaxTime, kHistogramTimeBuckets);
  }

  // Update the CALayer tree in the GPU process.
  {
    base::TimeTicks display_time;
    base::TimeDelta frame_interval;
#if BUILDFLAG(IS_MAC)
    display_time = GetDisplaytime(base::TimeTicks::Now());
    frame_interval = frame_interval_;
#endif
    TRACE_EVENT1("gpu", "CommitPresentedFrameToCA", "now_to_display",
                 (display_time - base::TimeTicks::Now()).InMicroseconds());
    ca_layer_tree_coordinator_->CommitPresentedFrameToCA(frame_interval,
                                                         display_time);
  }
}

bool ImageTransportSurfaceOverlayMacEGL::ScheduleCALayer(
    const ui::CARendererLayerParams& params,
    std::vector<gfx::MTLSharedEventFence> backpressure_fences) {
  ca_layer_tree_coordinator_->EnqueueBackpressureFences(
      std::move(backpressure_fences));
  static int scheduled = 0;
  if (scheduled < 16) {
    scheduled++;
    NSLog(@"[DeskBrowser] ScheduleCALayer #%d io_surface=%d rect=%d,%d %dx%d "
          @"opacity=%.2f solid=%d",
          scheduled, params.io_surface ? 1 : 0, params.rect.x(), params.rect.y(),
          params.rect.width(), params.rect.height(), params.opacity,
          params.io_surface ? 0 : 1);
  }
  return ca_layer_tree_coordinator_->GetPendingCARendererLayerTree()
      ->ScheduleCALayer(params);
}

bool ImageTransportSurfaceOverlayMacEGL::Resize(
    const gfx::Size& pixel_size,
    float scale_factor,
    const gfx::ColorSpace& color_space,
    bool has_alpha) {
  ca_layer_tree_coordinator_->Resize(pixel_size, scale_factor);
  return true;
}

void ImageTransportSurfaceOverlayMacEGL::SetMaxPendingSwaps(
    int max_pending_swaps) {
#if BUILDFLAG(IS_MAC)
  cap_max_pending_swaps_ = max_pending_swaps;

  // MaxCALayerTrees is equal to the number of max_pending_swaps + one
  // that has been displayed.
  ca_layer_tree_coordinator_->SetMaxCALayerTrees(cap_max_pending_swaps_ + 1);
#endif
}

#if BUILDFLAG(IS_MAC)
void ImageTransportSurfaceOverlayMacEGL::SetVSyncDisplayID(int64_t display_id,
                                                           bool force_update) {
  if (display_id_ == display_id && !force_update) {
    return;
  }

  vsync_callback_mac_ = nullptr;

  // Commit all pending frames before switching to the new monitor.
  while (ca_layer_tree_coordinator_->NumPendingSwaps()) {
    vsync_callback_mac_keep_alive_counter_ =
        std::max(vsync_callback_mac_keep_alive_counter_, 1);
    OnVSyncPresentation(ui::VSyncParamsMac());
  }

  display_link_mac_ = ui::DisplayLinkMac::GetForDisplay(display_id);

  display_id_ = display_id;
}

base::TimeTicks ImageTransportSurfaceOverlayMacEGL::GetDisplaytime(
    base::TimeTicks latch_time) {
  // From the CVDisplayLink params dump:
  // |next_display_time_| ~= |current_display_time_| + |frame_interval|.
  // params.display_time ~= params.callback_time + 1.5x |frame_interval|.

  // From the experiment, frames committed before (|current_display_time_| - 1.5
  // ms) will be displayed at the next display time. 1.5 ms is roughly the safe
  // zone for the latch deadline. The result is inconsistent in the experiment
  // if commit is too close to the display_time.
  constexpr base::TimeDelta kLatchBufferTime = base::Microseconds(1500);
  auto latch_deadline_for_next_display =
      current_display_time_ - kLatchBufferTime;
  if (latch_time < latch_deadline_for_next_display) {
    return next_display_time_;
  }

  // We just missed the |current_display_time|, the display will be at the next
  // one after |next_display_time_|.
  if (!frame_interval_.is_zero() && next_display_time_ != base::TimeTicks()) {
    base::TimeTicks present_time =
        latch_time.SnappedToNextTick(next_display_time_ - kLatchBufferTime,
                                     frame_interval_) +
        kLatchBufferTime + frame_interval_;
    return present_time;
  }

  // When there is no display_time info, just use the latch_time.
  // This only happens at the very first frame after the browser starts,
  return latch_time;
}

// The CVDisplayLink callback on the GPU thread.
void ImageTransportSurfaceOverlayMacEGL::OnVSyncPresentation(
    ui::VSyncParamsMac params) {
  // Documentation for the CVDisplayLink display_time
  // https://developer.apple.com/documentation/corevideo/cvdisplaylinkoutputcallback

  base::TimeDelta callback_delay;
  base::TimeDelta callback_timebase_to_display;
  if (params.callback_times_valid && params.display_times_valid) {
    callback_delay = base::TimeTicks::Now() - params.callback_timebase;
    callback_timebase_to_display =
        params.display_timebase - params.callback_timebase;
  }
  TRACE_EVENT2("gpu", "OnVSyncPresentation", "callback_timebase_to_display",
               callback_timebase_to_display.InMicroseconds(), "callback_delay",
               callback_delay.InMicroseconds());

  current_display_time_ = next_display_time_;

  if (params.display_times_valid) {
    next_display_time_ = params.display_timebase;
    frame_interval_ = params.display_interval;
  }

  if (params.callback_times_valid &&
      base::ShouldRecordSubsampledMetric(0.001)) {
    RecordVSyncCallbackDelay(base::TimeTicks::Now() - params.callback_timebase);
  }

  if (ca_layer_tree_coordinator_->NumPendingSwaps()) {
    CommitPresentedFrameToCA();
  }

  vsync_callback_mac_keep_alive_counter_--;

  if (vsync_callback_mac_keep_alive_counter_ == 0) {
    vsync_callback_mac_ = nullptr;
  }
}
#endif
}  // namespace gpu
