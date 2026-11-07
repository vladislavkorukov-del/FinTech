import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tactile feedback (Finora 1.27): a light tick under every tap on
/// something that reacts, firmer ones for saving, deleting and Finora's
/// moods. Turned off in Settings → «Тактильный отклик».
abstract final class Haptics {
  static bool enabled = true;

  /// Any tap on a button, row or switch.
  static void tap() {
    if (enabled) HapticFeedback.selectionClick();
  }

  static void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  /// Saved: a firm, pleasant tick.
  static Future<void> success() async {
    if (enabled) await HapticFeedback.mediumImpact();
  }

  /// Something needs attention: the phone's own buzz.
  static Future<void> warning() async {
    if (enabled) await HapticFeedback.vibrate();
  }
}

/// The theme's ink splash plus a haptic tick: every InkWell, button, chip,
/// switch and list row in the app answers the finger.
class HapticSplashFactory extends InteractiveInkFeatureFactory {
  const HapticSplashFactory(this.inner);
  final InteractiveInkFeatureFactory inner;

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    Haptics.tap();
    return inner.create(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: onRemoved,
    );
  }
}

/// [theme] with haptic splashes.
ThemeData withHaptics(ThemeData theme) =>
    theme.copyWith(splashFactory: HapticSplashFactory(theme.splashFactory));
