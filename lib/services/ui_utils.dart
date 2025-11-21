import 'package:flutter/widgets.dart';
import 'dart:math' as math;

/// Small collection of UI helpers to compute responsive sizes.
class UIUtils {
  UIUtils._();

  /// Returns the screen width in logical pixels.
  static double screenWidth(BuildContext ctx) => MediaQuery.of(ctx).size.width;

  /// Returns the screen height in logical pixels.
  static double screenHeight(BuildContext ctx) => MediaQuery.of(ctx).size.height;

  /// Compute a responsive card width as a fraction of the screen width,
  /// clamped to a maximum in pixels.
  static double responsiveCardWidth(BuildContext ctx, {double fraction = 0.5, double maxPx = 200.0}) {
    final w = screenWidth(ctx) * fraction;
    return math.min(w, maxPx);
  }

  /// Compute a responsive width as fraction of screen, clamped to [minPx, maxPx].
  static double responsiveWidthClamp(BuildContext ctx, double fraction, {double minPx = 0.0, double maxPx = double.infinity}) {
    final w = screenWidth(ctx) * fraction;
    return math.min(math.max(w, minPx), maxPx);
  }
}
