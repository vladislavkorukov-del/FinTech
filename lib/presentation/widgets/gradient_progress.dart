import 'package:flutter/material.dart';

/// A progress bar with a gradient (Release): a lighter, slightly shifted
/// shade flowing into the colour, a soft glow at the leading edge, and a
/// fill that pours in when it first appears and glides when it changes.
/// Drop-in for a determinate [LinearProgressIndicator].
class GradientProgress extends StatelessWidget {
  const GradientProgress({
    super.key,
    required this.value,
    this.minHeight = 6,
    this.color,
    this.backgroundColor,
    this.borderRadius,
  });
  final double? value;
  final double minHeight;
  final Color? color, backgroundColor;
  final BorderRadiusGeometry? borderRadius;

  /// The gradient's light end: lighter and turned a little round the wheel.
  static Color lightEnd(Color c) {
    final h = HSLColor.fromColor(c);
    return h
        .withHue((h.hue + 18) % 360)
        .withLightness((h.lightness + .16).clamp(0.0, .9))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    final track = backgroundColor ?? scheme.onSurface.withValues(alpha: .08);
    final radius = borderRadius ?? BorderRadius.circular(minHeight / 2);
    final target = (value ?? 0).clamp(0.0, 1.0);
    final still = MediaQuery.disableAnimationsOf(context);
    // The light theme is strict: a solid fill, no glow.
    final flat = Theme.of(context).brightness == Brightness.light;
    return Semantics(
      value: '${(target * 100).round()}%',
      child: SizedBox(
        height: minHeight,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: still ? target : 0, end: target),
          duration: still ? Duration.zero : const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: track,
                      borderRadius: radius,
                    ),
                  ),
                ),
                if (v > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: (box.maxWidth * v).clamp(minHeight, box.maxWidth),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        color: flat ? c : null,
                        gradient: flat
                            ? null
                            : LinearGradient(colors: [lightEnd(c), c]),
                        boxShadow: flat
                            ? null
                            : [
                                BoxShadow(
                                  color: c.withValues(alpha: .35),
                                  blurRadius: minHeight * 1.2,
                                ),
                              ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
