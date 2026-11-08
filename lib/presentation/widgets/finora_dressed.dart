import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/wardrobe.dart';
import 'finora_orb.dart';
import 'motion.dart';

/// 1.46: Finora in what she wears, with room around her for a tall hat,
/// a cape and a companion floating beside her. The box is
/// [widthFactor]×[heightFactor] of [size]; she is the [size] circle in it.
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

  static const widthFactor = 2.3, heightFactor = 2.05;

  /// Without a cape there is nothing below her: a shorter box.
  static double heightFor(List<WardrobeItem> outfit) =>
      outfit.any((i) => i.layer == WardrobeLayer.cape) ? heightFactor : 1.68;

  /// Her centre in the box, in sizes.
  static const centerX = 1.05, centerY = 1.0;

  @override
  Widget build(BuildContext context) {
    final r = size / 2;
    final cx = size * centerX, cy = size * centerY;
    final companions = [
      for (final i in outfit)
        if (i.layer == WardrobeLayer.frontAccessory) i,
    ];
    return SizedBox(
      width: size * widthFactor,
      height: size * heightFor(outfit),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: cx - r,
            top: cy - r,
            width: size,
            height: size,
            child: FinoraCharacter(
              size: size,
              moods: moods,
              rings: rings,
              outfit: outfit,
            ),
          ),
          for (final i in companions)
            Positioned(
              left: cx - r,
              top: cy - r,
              width: size,
              height: size,
              child: _Floating(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [WardrobePiece(i, r)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A companion gently floating up and down beside her.
class _Floating extends StatefulWidget {
  const _Floating({required this.child});
  final Widget child;
  @override
  State<_Floating> createState() => _FloatingState();
}

class _FloatingState extends State<_Floating>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.ambient(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) => Transform.translate(
      offset: Offset(0, math.sin(_c.value * 2 * math.pi) * 4),
      child: child,
    ),
  );
}
