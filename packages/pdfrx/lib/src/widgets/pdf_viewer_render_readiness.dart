import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Why a visible page is not (yet) completely rendered.
enum PdfPageRenderStatus {
  /// The page content drawn in the last painted frame is final for the current zoom and viewport.
  ready,

  /// The page has not been loaded yet (progressive loading).
  pageNotLoaded,

  /// The low resolution page preview is missing.
  previewMissing,

  /// The low resolution page preview exists but is dirty or has not the required scale.
  previewStale,

  /// The real-size partial image that the current zoom requires is missing.
  partialMissing,

  /// A real-size partial image exists but is dirty, has a different scale, or does not cover the visible area.
  partialStale,

  /// Rendering the image that is required for the current zoom failed.
  failed,
}

/// Pure evaluation of one visible page; kept free of viewer internals so that it can be unit tested.
///
/// The inputs describe the page images cached by the viewer and what the last painted frame required:
///
/// - [previewEnabled] / [previewScaleLimit]: whether low resolution previews are used and the scale they are rendered at.
/// - [pageScale]: the scale (zoom x device pixel ratio) of the page in the last painted frame.
/// - [requiredRect]: the part of the page (in document coordinates) that was visible in the last painted frame.
///
/// A page is [PdfPageRenderStatus.ready] only if every image that the painted frame depends on is present, clean, and
/// matches the required scale/area. When [pageScale] is greater than [previewScaleLimit] the full-resolution partial image
/// is required in addition to the preview, because only that image makes the frame final. [partialPossible] is false
/// when the visible part of the page is too small for the viewer to request a partial image at all. A recorded failure
/// ([previewFailed]/[partialFailed]) is only reported as [PdfPageRenderStatus.failed] while no retry is pending
/// ([previewPending]/[partialPending]); a pending retry makes the page merely not ready.
@visibleForTesting
PdfPageRenderStatus evaluatePageRenderStatus({
  required bool pageLoaded,
  required bool previewEnabled,
  required double previewScaleLimit,
  required double pageScale,
  required Rect requiredRect,
  double? previewScale,
  bool previewDirty = false,
  bool previewFailed = false,
  bool previewPending = false,
  double? partialScale,
  Rect? partialRect,
  bool partialDirty = false,
  bool partialPending = false,
  bool partialFailed = false,
  bool partialPossible = true,
}) {
  if (!pageLoaded) return PdfPageRenderStatus.pageNotLoaded;
  final partialRequired =
      (!previewEnabled || pageScale > previewScaleLimit) && partialPossible;
  if (previewEnabled) {
    if (previewFailed && !previewPending && previewScale != previewScaleLimit) {
      return PdfPageRenderStatus.failed;
    }
    if (previewScale == null) return PdfPageRenderStatus.previewMissing;
    if (previewDirty || previewScale != previewScaleLimit)
      return PdfPageRenderStatus.previewStale;
  }
  if (partialRequired) {
    if (partialFailed && !partialPending && (partialScale != pageScale || partialDirty)) {
      return PdfPageRenderStatus.failed;
    }
    if (partialScale == null || partialRect == null)
      return PdfPageRenderStatus.partialMissing;
    if (partialDirty ||
        partialPending ||
        partialScale != pageScale ||
        partialRect != requiredRect) {
      return PdfPageRenderStatus.partialStale;
    }
  }
  return PdfPageRenderStatus.ready;
}

/// Snapshot of the raster rendering readiness of a [PdfViewer].
///
/// "Ready" means: in the most recently painted frame, every page region that intersects the visible viewport was drawn
/// from its final (complete, clean, current-scale) raster image, not from a low resolution preview or a missing image.
///
/// It describes PDF page rasters only. Content drawn by the application on top of the viewer (e.g. overlays built with
/// [PdfViewerParams.pagePaintCallbacks] or widgets above the viewer) is not tracked; they paint in the same frame as the
/// page rasters, but applications that depend on asynchronous state of their own must wait for it separately.
@immutable
class PdfViewerRenderState {
  /// Creates a snapshot. Normally created by the viewer.
  const PdfViewerRenderState({
    required this.isReady,
    required this.generation,
    this.visiblePageNumbers = const [],
    this.pendingPageNumbers = const [],
    this.failedPageNumbers = const [],
    this.zoom = 0,
    this.devicePixelRatio = 1,
    this.viewSize = Size.zero,
    this.visibleRect = Rect.zero,
  });

  /// State of a viewer that is not attached, not initialized, or has been invalidated.
  const PdfViewerRenderState.notReady({this.generation = 0})
    : isReady = false,
      visiblePageNumbers = const [],
      pendingPageNumbers = const [],
      failedPageNumbers = const [],
      zoom = 0,
      devicePixelRatio = 1,
      viewSize = Size.zero,
      visibleRect = Rect.zero;

  /// Whether the last painted frame was drawn entirely from final raster images.
  final bool isReady;

  /// Increases every time the evaluated context changes (document, zoom, scroll, viewport, dirty pages).
  final int generation;

  /// 1-based numbers of the pages that intersect the visible viewport in the evaluated frame.
  final List<int> visiblePageNumbers;

  /// Visible pages whose raster is incomplete, stale or missing (and not failed).
  final List<int> pendingPageNumbers;

  /// Visible pages for which rendering the required image failed.
  final List<int> failedPageNumbers;

  /// Zoom ratio of the evaluated frame.
  final double zoom;

  /// Device pixel ratio of the evaluated frame.
  final double devicePixelRatio;

  /// View size (logical pixels) of the evaluated frame.
  final Size viewSize;

  /// Visible area in document coordinates of the evaluated frame.
  final Rect visibleRect;

  /// Whether rendering of at least one visible page failed.
  bool get hasFailures => failedPageNumbers.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is PdfViewerRenderState &&
      other.isReady == isReady &&
      other.generation == generation &&
      listEquals(other.visiblePageNumbers, visiblePageNumbers) &&
      listEquals(other.pendingPageNumbers, pendingPageNumbers) &&
      listEquals(other.failedPageNumbers, failedPageNumbers) &&
      other.zoom == zoom &&
      other.devicePixelRatio == devicePixelRatio &&
      other.viewSize == viewSize &&
      other.visibleRect == visibleRect;

  @override
  int get hashCode => Object.hash(
    isReady,
    generation,
    Object.hashAll(visiblePageNumbers),
    Object.hashAll(pendingPageNumbers),
    Object.hashAll(failedPageNumbers),
    zoom,
    devicePixelRatio,
    viewSize,
    visibleRect,
  );

  @override
  String toString() =>
      'PdfViewerRenderState(isReady: $isReady, generation: $generation, visible: $visiblePageNumbers, '
      'pending: $pendingPageNumbers, failed: $failedPageNumbers, zoom: $zoom, dpr: $devicePixelRatio, '
      'viewSize: $viewSize)';
}

/// Reason why [PdfViewerController.waitForRenderReady] did not complete normally.
enum PdfRenderReadyFailure {
  /// The timeout elapsed before the viewer became ready.
  timeout,

  /// Rendering a required image failed.
  renderFailed,

  /// The viewer was disposed or detached, or its document was replaced while waiting.
  detached,
}

/// Thrown by [PdfViewerController.waitForRenderReady] when readiness cannot be reached.
class PdfRenderReadyException implements Exception {
  /// Creates the exception.
  const PdfRenderReadyException(this.reason, this.state);

  /// What went wrong.
  final PdfRenderReadyFailure reason;

  /// The last known render state.
  final PdfViewerRenderState state;

  @override
  String toString() => 'PdfRenderReadyException(${reason.name}): $state';
}
