// Regression for post-pinch scale inertia.
//
// CONTRACT: ending a scale gesture must not trigger a large unintended
// post-release zoom excursion to the `minScale` floor.
//
// Root cause (established for MovoPDF as PDF-ZOOM-RESET-002): with no
// `scrollPhysics`, `_onScaleEnd` starts a friction "scale fling" to the raw
// `frictionSimulation.x(tFinal)`. When that target falls below `minScale`, the
// per-tick clamp in `_matrixScale` pins the viewer to the floor.
//
// The gesture below reproduces the shape captured on real hardware: a pinch
// released while still moving downward fast enough that the fling target falls
// below the floor, with the release scale itself still ABOVE the floor — so any
// collapse can only come from post-release inertia, never from an update clamp.
//
// This test lives in the package's own suite; it drives the forked
// `InteractiveViewer` directly (no PdfViewer, no PDFium), which is why
// `InteractiveViewer` does not need to be publicly exported for it.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide InteractiveViewer;
import 'package:flutter_test/flutter_test.dart';

import '../lib/src/widgets/interactive_viewer.dart';

const double kMinScale = 0.2;
const double kMaxScale = 8.0;
const double kStartScale = 1.24;

/// Numerical tolerance for "the settled scale is still the release scale".
const double kSettleTolerance = 1e-6;

void main() {
  testWidgets('scaleInertiaEnabled: false — settled scale stays at release', (
    tester,
  ) async {
    final tc = await _pumpViewer(tester, scaleInertia: false);
    final releaseScale = await _pinch(tester, tc);

    expect(
      releaseScale,
      greaterThan(kMinScale + 0.1),
      reason: 'calibration: the gesture must be released above the floor',
    );

    final settled = tc.value.getMaxScaleOnAxis();
    expect(
      settled,
      closeTo(releaseScale, kSettleTolerance),
      reason:
          'with scale inertia disabled the scale must remain exactly where the '
          'gesture left it (release=${releaseScale.toStringAsFixed(6)}, '
          'settled=${settled.toStringAsFixed(6)})',
    );
    expect(settled, greaterThan(kMinScale));
  });

  testWidgets('default (scaleInertiaEnabled: true) still overshoots', (
    tester,
  ) async {
    final tc = await _pumpViewer(tester, scaleInertia: true);
    final releaseScale = await _pinch(tester, tc);

    expect(releaseScale, greaterThan(kMinScale + 0.1));
    expect(
      tc.value.getMaxScaleOnAxis(),
      kMinScale,
      reason:
          'the default must still exhibit the excursion — if this stops '
          'reproducing, the unbounded fling target has been fixed and the '
          'opt-out has become redundant',
    );
  });
}

Future<TransformationController> _pumpViewer(
  WidgetTester tester, {
  required bool scaleInertia,
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

/// Runs the calibrated pinch; returns the scale at release.
Future<double> _pinch(WidgetTester tester, TransformationController tc) async {
  tc.value = Matrix4.identity()
    ..scaleByDouble(kStartScale, kStartScale, kStartScale, 1);
  await tester.pump();

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
