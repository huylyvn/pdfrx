import 'package:flutter/foundation.dart';

/// Bounds the target of a post-release **scale inertia** ("scale fling").
///
/// pdfrx starts the fling from the raw friction-simulation target
/// (`FrictionSimulation.x(tFinal)`). That target is unbounded, so a pinch that
/// is released while still moving can drive the scale far outside the release
/// position — in the pathological case to or through the `minScale` floor, where
/// the per-tick clamp then pins the viewer.
///
/// [maxExcursion] bounds how far the fling may travel **relative to the release
/// scale**: the returned target is always within `releaseScale * (1 -
/// maxExcursion) .. releaseScale * (1 + maxExcursion)` (then clamped into
/// `[minScale, maxScale]`). Expressing the bound as a fraction of the release
/// scale keeps the feel comparable across zoom levels, and makes pinch-in and
/// pinch-out symmetric.
///
/// Returns [rawTarget] unchanged when [maxExcursion] is `null`, which preserves
/// the unbounded upstream behaviour.
double boundedScaleFlingTarget({
  required double releaseScale,
  required double rawTarget,
  required double? maxExcursion,
  required double minScale,
  required double maxScale,
}) {
  if (maxExcursion == null) {
    return rawTarget;
  }
  assert(maxExcursion > 0 && maxExcursion < 1 && maxExcursion.isFinite);
  final lower = releaseScale * (1 - maxExcursion);
  final upper = releaseScale * (1 + maxExcursion);
  return clampDouble(clampDouble(rawTarget, lower, upper), minScale, maxScale);
}
