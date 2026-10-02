// Deterministic coverage for `InteractiveViewer.scaleGestureSensitivity`.
//
// CONTRACT: the live pinch mapping is `release = start * ratio ^ sensitivity`.
// `sensitivity == 1.0` must leave the mapping exactly as upstream, and any
// value > 1.0 must amplify the pinch symmetrically (pinch-in and pinch-out).
//
// The gesture is driven directly at the forked `InteractiveViewer` layer, and
// the scale is sampled after the last update and before any end event, so no
// post-release fling contributes to the measured value.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide InteractiveViewer;
import 'package:flutter_test/flutter_test.dart';

import '../lib/src/widgets/interactive_viewer.dart';

const double kStartScale = 1.24;

void main() {
  group('scaleGestureSensitivity', () {
    testWidgets('1.0 leaves the live mapping exactly as upstream', (
      tester,
    ) async {
      final release = await _liveRelease(tester, sensitivity: 1.0, ratio: 1.3);
      expect(release, closeTo(kStartScale * 1.3, 1e-9));
    });

    testWidgets('amplifies the live pinch ratio as an exponent (outward)', (
      tester,
    ) async {
      final r10 = await _liveRelease(tester, sensitivity: 1.0, ratio: 1.3);
      final r15 = await _liveRelease(tester, sensitivity: 1.5, ratio: 1.3);

      expect(
        r15,
        greaterThan(r10),
        reason: 'sensitivity > 1 must produce more zoom for the same movement',
      );
      expect(_logRatio(r15) / _logRatio(r10), closeTo(1.5, 1e-9));
    });

    testWidgets('is symmetric for pinch-in', (tester) async {
      final r10 = await _liveRelease(tester, sensitivity: 1.0, ratio: 0.8);
      final r15 = await _liveRelease(tester, sensitivity: 1.5, ratio: 0.8);

      expect(r15, lessThan(r10));
      expect(_logRatio(r15) / _logRatio(r10), closeTo(1.5, 1e-9));
    });
  });

  group('scaleGestureSensitivity validation', () {
    test('accepts any positive finite value', () {
      for (final good in <double>[0.5, 1.0, 1.6, 3.0]) {
        expect(
          () => InteractiveViewer(
            scaleGestureSensitivity: good,
            child: const SizedBox(),
          ),
          returnsNormally,
          reason: 'scaleGestureSensitivity=$good must be accepted',
        );
      }
    });

    test('rejects zero, negative, NaN and infinity', () {
      for (final bad in <double>[0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => InteractiveViewer(
            scaleGestureSensitivity: bad,
            child: const SizedBox(),
          ),
          throwsAssertionError,
          reason: 'scaleGestureSensitivity=$bad must be rejected',
        );
      }
    });
  });
}

double _logRatio(double release) => math.log(release / kStartScale);

/// Runs a pinch whose gesture scale ratio ends at [ratio]; returns the scale
/// after the last update (no end event is sent, so no fling is involved).
Future<double> _liveRelease(
  WidgetTester tester, {
  required double sensitivity,
  required double ratio,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 800);
  addTearDown(tester.view.reset);

  final tc = TransformationController();
  addTearDown(tc.dispose);

  // A unique key forces a fresh State per measurement; without it the
  // InteractiveViewer State (and its `_scaleStart`) is reused across pumps.
  final id = _nextDevice++;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 700,
            height: 700,
            child: InteractiveViewer(
              key: ValueKey<int>(id),
              transformationController: tc,
              constrained: false,
              minScale: 0.2,
              maxScale: 8.0,
              scaleGestureSensitivity: sensitivity,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: const SizedBox(width: 600, height: 800),
            ),
          ),
        ),
      ),
    ),
  );

  tc.value = Matrix4.identity()
    ..scaleByDouble(kStartScale, kStartScale, kStartScale, 1);
  await tester.pump();

  const pos = Offset(400, 400);
  final device = id;
  var t = Duration.zero;
  await tester.sendEventToBinding(
    PointerPanZoomStartEvent(
      device: device,
      pointer: device,
      position: pos,
      timeStamp: t,
    ),
  );
  for (var i = 0; i <= 10; i++) {
    final scale = 1.0 + (ratio - 1.0) * (i / 10);
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        device: device,
        pointer: device,
        position: pos,
        pan: Offset.zero,
        panDelta: Offset.zero,
        scale: scale,
        rotation: 0,
        timeStamp: t,
      ),
    );
    t += const Duration(milliseconds: 16);
    await tester.pump(const Duration(milliseconds: 4));
  }

  final release = tc.value.getMaxScaleOnAxis();

  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(
      device: device,
      pointer: device,
      position: pos,
      timeStamp: t,
    ),
  );
  await tester.pump(const Duration(milliseconds: 4));

  return release;
}

/// Each gesture needs its own pointer id: the test binding keeps a hit test per
/// pointer, and a start event for a pointer that has not ended asserts.
int _nextDevice = 71;
