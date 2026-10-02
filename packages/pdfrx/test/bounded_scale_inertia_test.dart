// Deterministic coverage for PDF-ZOOM-INERTIA-003 (bounded scale inertia).
//
// CONTRACT: with `scaleInertiaMaxExcursion` set, a post-release scale fling may
// continue past the release scale (useful momentum) but its total excursion is
// bounded to that fraction of the release scale, and it must never be the raw
// unbounded target that drove the viewer to the `minScale` floor.
//
// The default (`scaleInertiaMaxExcursion == null`) must remain byte-identical to
// pdfrx's existing unbounded behaviour; `scaleInertiaEnabled: false` must still
// produce zero post-release movement.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide InteractiveViewer;
import 'package:flutter_test/flutter_test.dart';

import '../lib/src/widgets/interactive_viewer.dart';
import '../lib/src/widgets/scale_inertia.dart';

const double kMinScale = 0.2;
const double kMaxScale = 8.0;
const double kStartScale = 1.24;

/// Physical regression calibration (PDF-ZOOM-RESET-002): a pinch released at
/// this scale while still moving downward, whose unbounded fling target fell
/// below the floor.
const double kPathologicalRelease = 0.538160;
const double kPathologicalRawTarget = -0.025031;

void main() {
  group('boundedScaleFlingTarget', () {
    test('null excursion returns the raw (upstream) target unchanged', () {
      expect(
        boundedScaleFlingTarget(
          releaseScale: 0.538160,
          rawTarget: kPathologicalRawTarget,
          maxExcursion: null,
          minScale: kMinScale,
          maxScale: kMaxScale,
        ),
        kPathologicalRawTarget,
      );
    });

    test('a target below the bound is pulled up to release * (1 - r)', () {
      expect(
        boundedScaleFlingTarget(
          releaseScale: 1.0,
          rawTarget: -5.0,
          maxExcursion: 0.25,
          minScale: kMinScale,
          maxScale: kMaxScale,
        ),
        closeTo(0.75, 1e-12),
      );
    });

    test('a target above the bound is pulled down to release * (1 + r)', () {
      expect(
        boundedScaleFlingTarget(
          releaseScale: 1.0,
          rawTarget: 40.0,
          maxExcursion: 0.25,
          minScale: kMinScale,
          maxScale: kMaxScale,
        ),
        closeTo(1.25, 1e-12),
      );
    });

    test('a target inside the bound is returned unchanged', () {
      expect(
        boundedScaleFlingTarget(
          releaseScale: 2.0,
          rawTarget: 2.3,
          maxExcursion: 0.25,
          minScale: kMinScale,
          maxScale: kMaxScale,
        ),
        closeTo(2.3, 1e-12),
      );
    });

    test('the global floor is still respected after bounding', () {
      // release 0.24 with r = 0.5 -> lower bound 0.12, below minScale.
      expect(
        boundedScaleFlingTarget(
          releaseScale: 0.24,
          rawTarget: -10.0,
          maxExcursion: 0.5,
          minScale: kMinScale,
          maxScale: kMaxScale,
        ),
        closeTo(kMinScale, 1e-12),
      );
    });

    test('the pathological release no longer targets the floor', () {
      final bounded = boundedScaleFlingTarget(
        releaseScale: kPathologicalRelease,
        rawTarget: kPathologicalRawTarget,
        maxExcursion: 0.25,
        minScale: kMinScale,
        maxScale: kMaxScale,
      );
      expect(bounded, closeTo(kPathologicalRelease * 0.75, 1e-12));
      expect(bounded, greaterThan(kMinScale));
      expect(
        (bounded - kPathologicalRelease).abs(),
        lessThanOrEqualTo(0.25 * kPathologicalRelease + 1e-12),
      );
    });
  });

  group('bounded scale inertia (widget)', () {
    testWidgets('pathological pinch no longer settles on the floor', (
      tester,
    ) async {
      final tc = await _pumpViewer(tester, maxExcursion: 0.25);
      final release = await _pinch(tester, tc, _inwardSchedule());

      expect(
        release,
        closeTo(kPathologicalRelease, 1e-3),
        reason: 'calibration: gesture should reproduce the recorded release',
      );

      final settled = tc.value.getMaxScaleOnAxis();
      expect(
        settled,
        greaterThan(kMinScale + 0.1),
        reason:
            'bounded inertia must not land on the minScale floor '
            '(release=${release.toStringAsFixed(6)}, '
            'settled=${settled.toStringAsFixed(6)})',
      );
    });

    testWidgets('momentum exists but stays within the bound', (tester) async {
      final tc = await _pumpViewer(tester, maxExcursion: 0.25);
      final release = await _pinch(tester, tc, _inwardSchedule());
      final settled = tc.value.getMaxScaleOnAxis();

      expect(
        settled,
        isNot(closeTo(release, 1e-6)),
        reason:
            'a fast pinch with bounded inertia must still move after release',
      );
      expect(
        settled,
        lessThan(release),
        reason: 'a downward-released pinch must continue inward',
      );
      expect(
        (settled - release).abs(),
        lessThanOrEqualTo(0.25 * release + 1e-6),
        reason: 'excursion must not exceed the configured fraction',
      );
      expect(settled, closeTo(release * 0.75, 1e-3));
    });

    testWidgets('pinch-out momentum continues outward', (tester) async {
      final tc = await _pumpViewer(tester, maxExcursion: 0.25);
      final release = await _pinch(tester, tc, _outwardSchedule());
      final settled = tc.value.getMaxScaleOnAxis();

      expect(settled, greaterThan(release));
      expect(
        (settled - release).abs(),
        lessThanOrEqualTo(0.25 * release + 1e-6),
      );
    });

    testWidgets('scaleInertiaEnabled: false still yields zero movement', (
      tester,
    ) async {
      final tc = await _pumpViewer(
        tester,
        scaleInertia: false,
        maxExcursion: 0.25,
      );
      final release = await _pinch(tester, tc, _inwardSchedule());
      expect(
        tc.value.getMaxScaleOnAxis(),
        closeTo(release, 1e-6),
        reason: 'the opt-out must win over any excursion bound',
      );
    });

    testWidgets('null excursion preserves the unbounded upstream target', (
      tester,
    ) async {
      final tc = await _pumpViewer(tester, maxExcursion: null);
      await _pinch(tester, tc, _inwardSchedule());
      expect(
        tc.value.getMaxScaleOnAxis(),
        kMinScale,
        reason:
            'default behaviour must still overshoot — this is the bug the '
            'bounded model fixes, and the default must not change',
      );
    });
  });

  group('scaleInertiaMaxExcursion validation', () {
    test('accepts null and any finite value in (0, 1)', () {
      for (final good in <double?>[null, 0.001, 0.25, 0.999]) {
        expect(
          () => InteractiveViewer(
            scaleInertiaMaxExcursion: good,
            child: const SizedBox(),
          ),
          returnsNormally,
          reason: 'scaleInertiaMaxExcursion=$good must be accepted',
        );
      }
    });

    test('rejects zero, one, out-of-range, NaN and infinity', () {
      for (final bad in <double>[
        0.0,
        1.0,
        -0.1,
        2.0,
        double.nan,
        double.infinity,
      ]) {
        expect(
          () => InteractiveViewer(
            scaleInertiaMaxExcursion: bad,
            child: const SizedBox(),
          ),
          throwsAssertionError,
          reason: 'scaleInertiaMaxExcursion=$bad must be rejected',
        );
      }
    });
  });
}

/// Inward schedule: rises, then reverses fast so the terminal scale velocity is
/// strongly negative. Matches the calibrations in `scale_inertia_test.dart`.
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

/// Mirror of [_inwardSchedule]: falls, then reverses fast upward, so the
/// terminal scale velocity is strongly positive.
List<(Duration, double)> _outwardSchedule() {
  final sched = <(Duration, double)>[];
  var t = Duration.zero;
  for (var i = 0; i <= 10; i++) {
    sched.add((t, kStartScale * (1.0 - 0.015 * i)));
    t += const Duration(milliseconds: 16);
  }
  for (var i = 0; i < 8; i++) {
    sched.add((t, kStartScale * (0.95 + 0.10 * i)));
    t += const Duration(milliseconds: 3);
  }
  return sched;
}

Future<TransformationController> _pumpViewer(
  WidgetTester tester, {
  bool scaleInertia = true,
  double? maxExcursion,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 800);
  addTearDown(tester.view.reset);

  final tc = TransformationController();
  addTearDown(tc.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 700,
            height: 700,
            child: InteractiveViewer(
              transformationController: tc,
              constrained: false,
              minScale: kMinScale,
              maxScale: kMaxScale,
              scaleInertiaEnabled: scaleInertia,
              scaleInertiaMaxExcursion: maxExcursion,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: const SizedBox(width: 600, height: 800),
            ),
          ),
        ),
      ),
    ),
  );
  return tc;
}

/// Runs [sched] as a pinch; returns the scale at release (after the last update,
/// before the end event).
Future<double> _pinch(
  WidgetTester tester,
  TransformationController tc,
  List<(Duration, double)> sched,
) async {
  tc.value = Matrix4.identity()
    ..scaleByDouble(kStartScale, kStartScale, kStartScale, 1);
  await tester.pump();

  const pos = Offset(400, 400);
  const device = 71;
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

  final releaseScale = tc.value.getMaxScaleOnAxis();

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
  return releaseScale;
}
