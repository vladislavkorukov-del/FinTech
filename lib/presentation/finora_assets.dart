import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../domain/achievements.dart';
import 'widgets/finora_orb.dart';

/// 2.2: achievement cards no longer carry drawings of Finora with a face —
/// each card shows her as she is now, a sphere of light on a deep glowing
/// card.
abstract final class FinoraAssets {
  /// Width to height of a card.
  static const cardRatio = 1024 / 553;

  /// There are no illustrations any more: every card draws Finora.
  static String? achievementArt(AchievementDefinition d) => null;
}

/// A card with Finora: her light on a deep gradient.
class FinoraArt extends StatelessWidget {
  const FinoraArt({
    super.key,
    this.name,
    this.fit = BoxFit.cover,
    this.locked = false,
    this.semanticLabel,
    this.frame = true,
  });

  /// Kept for callers; there are no named pictures any more.
  final String? name;
  final BoxFit fit;

  /// Not received yet: no colour, dimmed.
  final bool locked;
  final String? semanticLabel;

  /// False: no glowing card behind her (small pictures in lists).
  final bool frame;

  static const _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final glow = FinoraOrbPainter.theme;
    Widget child = LayoutBuilder(
      builder: (context, box) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: frame
              ? RadialGradient(
                  colors: [
                    Color.lerp(glow, const Color(0xFF0B1324), .55)!,
                    const Color(0xFF0B1324),
                  ],
                  radius: .9,
                )
              : null,
        ),
        child: Center(
          child: FinoraCharacter(
            size: (box.biggest.shortestSide * .7).clamp(24, 160),
            rings: false,
          ),
        ),
      ),
    );
    if (semanticLabel != null) {
      child = Semantics(label: semanticLabel, image: true, child: child);
    }
    if (locked) {
      child = Opacity(
        opacity: .45,
        child: ColorFiltered(colorFilter: _grey, child: child),
      );
    }
    return child;
  }
}
