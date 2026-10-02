// Deterministic widget regression for the COMBINED MovoPDF production
// configuration selected as `g16` (PDF-ZOOM-INERTIA-003):
//
//   scaleInertiaEnabled:      true
//   scaleInertiaMaxExcursion: 0.25
//   scaleGestureSensitivity:  1.6
//
// It drives one inward pinch end-to-end and asserts, together:
//   * the live gain applies   (ln(release/start) scales by 1.6 vs upstream);
//   * the fling is bounded     (|settled − release| ≤ 0.25 · release);
//   * momentum exists          (settled != release);
//   * the viewer never lands on the minScale floor.
//
// The movo-* constants mirror `lib/model/document_session.dart`. If those values
// change, this test and the MovoPDF `viewer_config_test.dart` must change
// together.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide InteractiveViewer;
import 'package:flutter_test/flutter_test.dart';

import '../lib/src/widgets/interactive_viewer.dart';

const double kMinScale = 0.2;
const double kMaxScale = 8.0;
const double kStartScale = 1.24;

/// The selected MovoPDF production values.
const double kMovoExcursion = 0.25;
const double kMovoSensitivity = 1.6;

void main() {
  testWidgets(
    'combined MovoPDF config: live gain applies and the fling stays bounded',
    (tester) async {
      // Reference run: the same gesture with upstream settings (gain 1, no bound).
      final upstream = await _measure(
        tester,
        sensitivity: 1.0,
        excursion: null,
      );
      // Production run: the exact combined MovoPDF configuration.
      final movo = await _measure(
        tester,
        sensitivity: kMovoSensitivity,
        excursion: kMovoExcursion,
      );

      // ---- live gain -------------------------------------------------------
      expect(
        movo.release,
        lessThan(upstream.release),
        reason: 'gain 1.6 must zoom further for the same finger movement',
      );
      expect(
        _logRatio(movo.release) / _logRatio(upstream.release),
        closeTo(kMovoSensitivity, 1e-6),
        reason: 'ln(release/start) must scale exactly by the sensitivity',
      );

      // ---- bounded, useful inertia ----------------------------------------
      expect(
        movo.settled,
        isNot(closeTo(movo.release, 1e-6)),
        reason:
            'a fast pinch with bounded inertia must still move after release',
      );
      expect(
        movo.settled,
        lessThan(movo.release),
        reason: 'an inward-released pinch must continue inward',
      );
      expect(
        (movo.settled - movo.release).abs(),
        lessThanOrEqualTo(kMovoExcursion * movo.release + 1e-6),
        reason: 'excursion must not exceed the configured 0.25 fraction',
      );
      expect(
        movo.settled,
        greaterThan(kMinScale),
        reason: 'the combined config must never land on the minScale floor',
      );
    },
  );
}

double _logRatio(double release) => math.log(release / kStartScale);

/// One pinch measurement: `release` is sampled after the last update (before the
/// end event), `settled` after the fling completes.
Future<({double release, double settled})> _measure(
  WidgetTester tester, {
  required double sensitivity,
  required double? excursion,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 800);
  addTearDown(tester.view.reset);

  final tc = TransformationController();
  addTearDown(tc.dispose);

  // A unique key forces a fresh State per measurement (otherwise `_scaleStart`
  // is reused across pumps).
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
              minScale: kMinScale,
              maxScale: kMaxScale,
              scaleInertiaEnabled: true,
              scaleInertiaMaxExcursion: excursion,
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

  final sched = _inwardSchedule();
  const pos = Offset(400, 400);
  final device = id;
  await tester.sendEventToBinding(
    PointerPanZoomStartEvent(
      device: device,
      pointer: device,
      position: pos,
      timeStamp: sched.first.$1,
    ),
  );
  for (final (ts, scale) in sched) {
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        device: device,
        pointer: device,
        position: pos,
        pan: Offset.zero,
        panDelta: Offset.zero,
        scale: scale,
        rotation: 0,
        timeStamp: ts,
      ),
    );
    await tester.pump(const Duration(milliseconds: 4));
  }

  final release = tc.value.getMaxScaleOnAxis();

  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(
      device: device,
      pointer: device,
      position: pos,
      timeStamp: sched.last.$1 + const Duration(milliseconds: 2),
    ),
  );
  await tester.pump(const Duration(milliseconds: 4));
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }

  return (release: release, settled: tc.value.getMaxScaleOnAxis());
}

/// Rises, then reverses fast downward — the calibrated shape that produced the
/// PDF-ZOOM-RESET-002 collapse.
List<(Duration, double)> _inwardSchedule() {
  final sched = <(Duration, double)>[];
  var t = Duration.zero;
  for (var i = 0; i <= 10; i++) {
    sched.add((t, kStartScale * (1 + 0.15 * (i / 10))));
    t += const Duration(milliseconds: 16);
  }
  for (var i = 0; i < 8; i++) {
    sched.add((t, kStartScale * (1.05 - 0.10 * i)));
    t += const Duration(milliseconds: 3);
  }
  return sched;
}

int _nextDevice = 71;
