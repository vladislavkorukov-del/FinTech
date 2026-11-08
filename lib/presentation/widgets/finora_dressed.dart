import 'package:flutter/material.dart';

import '../../domain/wardrobe.dart';
import 'finora_orb.dart';

/// 1.46: Finora in what she wears, with room around her for a tall hat
/// and a wide cape. The box is [widthFactor]×[heightFactor] of [size]; she
/// is the [size] circle in it.
class FinoraDressed extends StatelessWidget {
  const FinoraDressed({
    super.key,
    required this.outfit,
    this.size = 120,
    this.moods = const [FinoraMood.idle],
    this.rings = true,
  });

  final List<WardrobeItem> outfit;
  final double size;
  final List<FinoraMood> moods;
  final bool rings;

  /// 1.47: capes spread to about twice her width.
  static const widthFactor = 2.25, heightFactor = 1.8;

  /// Her centre in the box, in sizes.
  static const centerX = widthFactor / 2, centerY = 1.05;

  @override
  Widget build(BuildContext context) {
    final r = size / 2;
    return SizedBox(
      width: size * widthFactor,
      height: size * heightFactor,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: size * centerX - r,
            top: size * centerY - r,
            width: size,
            height: size,
            child: FinoraCharacter(
              size: size,
              moods: moods,
              rings: rings,
              outfit: outfit,
            ),
          ),
        ],
      ),
    );
  }
}
