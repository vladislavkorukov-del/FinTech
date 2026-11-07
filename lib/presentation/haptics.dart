import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tactile feedback (Finora 1.27, stronger in 1.34): a firm tick under every
/// tap on something that reacts, stronger ones for saving, deleting and
/// Finora's moods. On Android it drives the vibration motor directly (the
/// system «touch feedback» is barely felt on many phones); elsewhere — the
/// strongest system impacts. Turned off in Settings → «Тактильный отклик».
abstract final class Haptics {
  static bool enabled = true;
  static const _channel = MethodChannel('finora/system');
  static bool? _native;

  /// One pulse of [ms] at [amplitude] (1…255), or [fallback] without the
  /// bridge (tests, other platforms).
  static void _pulse(int ms, int amplitude, Future<void> Function() fallback) {
    if (!enabled) return;
    if (_native == false) {
      unawaited(fallback());
      return;
    }
    unawaited(
      _channel
          .invokeMethod<bool>('vibrate', {'ms': ms, 'amplitude': amplitude})
          .then((_) => _native = true)
          .catchError((Object _) {
            _native = false;
            return fallback().then((_) => false);
          }),
    );
  }

  /// Any tap on a button, row or switch.
  static void tap() => _pulse(22, 170, HapticFeedback.lightImpact);

  static void light() => _pulse(26, 190, HapticFeedback.mediumImpact);

  static void medium() => _pulse(36, 225, HapticFeedback.mediumImpact);

  static void heavy() => _pulse(55, 255, HapticFeedback.heavyImpact);

  /// Saved: a firm, pleasant tick.
  static Future<void> success() async =>
      _pulse(45, 245, HapticFeedback.heavyImpact);

  /// Something needs attention: a long buzz.
  static Future<void> warning() async =>
      _pulse(160, 255, HapticFeedback.vibrate);
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
