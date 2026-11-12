import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// Pure evaluation of one visible page (PDFRX-RENDER-READY-001 contract).
///
/// A page is ready only if every image the painted frame depends on is present,
/// clean, and matches the required scale/area.
void main() {
  const required = Rect.fromLTWH(10, 20, 300, 400);
  PdfPageRenderStatus eval({
    bool pageLoaded = true,
    bool previewEnabled = true,
    double limit = 200 / 72,
    double pageScale = 1.0,
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
  }) => evaluatePageRenderStatus(
    pageLoaded: pageLoaded,
    previewEnabled: previewEnabled,
    previewScaleLimit: limit,
    pageScale: pageScale,
    requiredRect: required,
    previewScale: previewScale,
    previewDirty: previewDirty,
    previewFailed: previewFailed,
    previewPending: previewPending,
    partialScale: partialScale,
    partialRect: partialRect,
    partialDirty: partialDirty,
    partialPending: partialPending,
    partialFailed: partialFailed,
    partialPossible: partialPossible,
  );
  const lim = 200 / 72;

  group('preview regime (pageScale <= preview scale)', () {
    test('ready with a clean preview at the right scale; no partial needed', () {
      expect(eval(previewScale: lim), PdfPageRenderStatus.ready);
      expect(eval(previewScale: lim, pageScale: lim), PdfPageRenderStatus.ready);
    });
    test('not ready without a preview', () => expect(eval(), PdfPageRenderStatus.previewMissing));
    test('not ready with a dirty preview', () {
      expect(eval(previewScale: lim, previewDirty: true), PdfPageRenderStatus.previewStale);
    });
    test('not ready with a preview at a different scale', () {
      expect(eval(previewScale: 1.0), PdfPageRenderStatus.previewStale);
    });
    test('not ready while the page is not loaded', () {
      expect(eval(pageLoaded: false, previewScale: lim), PdfPageRenderStatus.pageNotLoaded);
    });
  });

  group('partial regime (pageScale > preview scale): the preview alone is NOT final', () {
    test('missing partial', () {
      expect(eval(pageScale: 3, previewScale: lim), PdfPageRenderStatus.partialMissing);
    });
    test('stale partial: wrong scale, wrong rect, dirty, pending request', () {
      expect(eval(pageScale: 3, previewScale: lim, partialScale: 2.9, partialRect: required), PdfPageRenderStatus.partialStale);
      expect(
        eval(pageScale: 3, previewScale: lim, partialScale: 3, partialRect: const Rect.fromLTWH(10, 20, 300, 399)),
        PdfPageRenderStatus.partialStale,
      );
      expect(
        eval(pageScale: 3, previewScale: lim, partialScale: 3, partialRect: required, partialDirty: true),
        PdfPageRenderStatus.partialStale,
      );
      expect(
        eval(pageScale: 3, previewScale: lim, partialScale: 3, partialRect: required, partialPending: true),
        PdfPageRenderStatus.partialStale,
      );
    });
    test('ready only with a clean partial of the current scale covering exactly the visible area', () {
      expect(eval(pageScale: 3, previewScale: lim, partialScale: 3, partialRect: required), PdfPageRenderStatus.ready);
      expect(eval(pageScale: 8, previewScale: lim, partialScale: 8, partialRect: required), PdfPageRenderStatus.ready);
    });
    test('both stages are required: a good partial with a missing preview is not ready', () {
      expect(eval(pageScale: 3, partialScale: 3, partialRect: required), PdfPageRenderStatus.previewMissing);
    });
    test('a sliver too small to request a partial does not block readiness', () {
      expect(eval(pageScale: 3, previewScale: lim, partialPossible: false), PdfPageRenderStatus.ready);
    });
  });

  group('previews disabled: only the partial image counts', () {
    test('requires a partial even at low zoom', () {
      expect(eval(previewEnabled: false, pageScale: 1), PdfPageRenderStatus.partialMissing);
      expect(
        eval(previewEnabled: false, pageScale: 1, partialScale: 1, partialRect: required),
        PdfPageRenderStatus.ready,
      );
    });
  });

  group('failures are never reported as ready', () {
    test('failed preview at the required scale', () {
      expect(eval(previewFailed: true), PdfPageRenderStatus.failed);
    });
    test('failed partial at the required scale', () {
      expect(eval(pageScale: 3, previewScale: lim, partialFailed: true), PdfPageRenderStatus.failed);
    });
    test('a failure is not sticky while a retry is pending (superseded attempt)', () {
      expect(eval(previewFailed: true, previewPending: true), PdfPageRenderStatus.previewMissing);
      expect(
        eval(pageScale: 3, previewScale: lim, partialFailed: true, partialPending: true),
        PdfPageRenderStatus.partialMissing,
      );
    });
    test('a later success clears the failure', () {
      expect(
        eval(pageScale: 3, previewScale: lim, partialFailed: true, partialScale: 3, partialRect: required),
        PdfPageRenderStatus.ready,
      );
    });
  });

  group('PdfViewerRenderState', () {
    test('notReady is not ready and has no pages', () {
      const s = PdfViewerRenderState.notReady(generation: 4);
      expect(s.isReady, isFalse);
      expect(s.generation, 4);
      expect(s.hasFailures, isFalse);
      expect(s.visiblePageNumbers, isEmpty);
    });
    test('value equality and hasFailures', () {
      const a = PdfViewerRenderState(isReady: false, generation: 1, visiblePageNumbers: [3], failedPageNumbers: [3]);
      const b = PdfViewerRenderState(isReady: false, generation: 1, visiblePageNumbers: [3], failedPageNumbers: [3]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.hasFailures, isTrue);
      expect(a == const PdfViewerRenderState(isReady: false, generation: 2, visiblePageNumbers: [3]), isFalse);
    });
    test('PdfRenderReadyException reports reason and state', () {
      const e = PdfRenderReadyException(PdfRenderReadyFailure.timeout, PdfViewerRenderState.notReady());
      expect(e.reason, PdfRenderReadyFailure.timeout);
      expect(e.toString(), contains('timeout'));
    });
  });

  group('unattached controller', () {
    test('is not render-ready and waitForRenderReady fails as detached', () async {
      final c = PdfViewerController();
      expect(c.isRenderReady, isFalse);
      expect(c.renderState.value.isReady, isFalse);
      await expectLater(
        c.waitForRenderReady(timeout: const Duration(milliseconds: 50)),
        throwsA(isA<PdfRenderReadyException>().having((e) => e.reason, 'reason', PdfRenderReadyFailure.detached)),
      );
    });
  });
}
