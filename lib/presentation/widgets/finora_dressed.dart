import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/wardrobe.dart';
import 'finora_orb.dart';
import 'motion.dart';

/// Geometry from the supplied cape_placement.json. [bodySize] is Finora's
/// diameter, never the cape width. One scale applies to the complete source
/// canvas and the body rectangle, including non-square cape/companion assets.
@immutable
class FinoraOutfitGeometry {
  const FinoraOutfitGeometry(this.bodySize);

  final double bodySize;
  static const sourceCanvas = Size(1536, 1024);
  static const sourceBody = Rect.fromLTWH(390, 130, 756, 756);

  // Space for the existing cheer's scale <=1.2, turn <=.14rad and vertical
  // drift/hop. Keep the whole cape inside the component on every frame.
  static const widthFactor = 2.7, heightFactor = 2.2;
  static const centerX = 1.35, centerY = 1.17;

  double get scale => bodySize / sourceBody.width;
  Size get size => Size(bodySize * widthFactor, bodySize * heightFactor);
  Rect get bodyRect => Rect.fromCenter(
    center: Offset(bodySize * centerX, bodySize * centerY),
    width: bodySize,
    height: bodySize,
  );
  Rect get capeRect => Rect.fromLTWH(
    bodyRect.left - sourceBody.left * scale,
    bodyRect.top - sourceBody.top * scale,
    sourceCanvas.width * scale,
    sourceCanvas.height * scale,
  );

  Rect companionRect(WardrobeItem item) {
    final r = bodySize / 2;
    final fit = item.fit;
    final width = fit.width * bodySize;
    final height = width / item.ratio;
    return Rect.fromLTWH(
      bodyRect.center.dx + fit.x * r - width * (fit.anchorX + 1) / 2,
      bodyRect.center.dy + fit.y * r - height * (fit.anchorY + 1) / 2,
      width,
      height,
    );
  }
}

/// The supplied full cape, with its central orb silhouette excluded rather than
/// painted over. Its hole follows the exact breathing radius of Finora's painter.
/// [FinoraCharacter] places this below the body in the same motion transform.
class FinoraCapeLayer extends StatelessWidget {
  const FinoraCapeLayer({
    super.key,
    required this.item,
    required this.bodySize,
    this.radiusScale = 1,
  });

  final WardrobeItem item;
  final double bodySize, radiusScale;

  @override
  Widget build(BuildContext context) {
    final scale = bodySize / FinoraOutfitGeometry.sourceBody.width;
    final body = FinoraOutfitGeometry.sourceBody;
    final canvas = FinoraOutfitGeometry.sourceCanvas;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -body.left * scale,
          top: -body.top * scale,
          width: canvas.width * scale,
          height: canvas.height * scale,
          child: ClipPath(
            key: ValueKey('wardrobe-cape-mask-${item.id}'),
            clipBehavior: Clip.antiAlias,
            clipper: CapeOutsideBodyClipper(
              bodyRect: Rect.fromLTWH(
                body.left * scale,
                body.top * scale,
                body.width * scale,
                body.height * scale,
              ),
              radiusScale: radiusScale,
            ),
            child: Image.asset(
              item.asset,
              cacheWidth:
                  (canvas.width *
                          scale *
                          MediaQuery.devicePixelRatioOf(context) *
                          2)
                      .ceil()
                      .clamp(1, 1536),
              fit: BoxFit.fill,
              isAntiAlias: true,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// A true transparent, antialiased hole: it neither fills nor changes the body.
class CapeOutsideBodyClipper extends CustomClipper<Path> {
  const CapeOutsideBodyClipper({required this.bodyRect, this.radiusScale = 1});
  final Rect bodyRect;
  final double radiusScale;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addOval(
      Rect.fromCircle(
        center: bodyRect.center,
        radius: bodyRect.width / 2 * radiusScale,
      ),
    );

  @override
  bool shouldReclip(CapeOutsideBodyClipper oldClipper) =>
      oldClipper.bodyRect != bodyRect || oldClipper.radiusScale != radiusScale;
}

/// One Finora, a cape attached behind her, and an independently placed companion.
/// A common motion-safe box prevents either accessory from painting over UI.
class FinoraDressed extends StatelessWidget {
  const FinoraDressed({
    super.key,
    required this.outfit,
    this.size = 120,
    this.moods = const [FinoraMood.idle],
    this.rings = true,
    this.companionScale = 1,
    this.companionTilt = 0,
    this.companionSleeping = false,
    this.onCompanionTap,
  });

  final List<WardrobeItem> outfit;
  final double size;
  final List<FinoraMood> moods;
  final bool rings;
  final double companionScale, companionTilt;
  final bool companionSleeping;
  final VoidCallback? onCompanionTap;

  static const widthFactor = FinoraOutfitGeometry.widthFactor;
  static const heightFactor = FinoraOutfitGeometry.heightFactor;
  static const centerX = FinoraOutfitGeometry.centerX;
  static const centerY = FinoraOutfitGeometry.centerY;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final diameter = constraints.hasBoundedWidth
          ? math.min(size, constraints.maxWidth / widthFactor)
          : size;
      final geometry = FinoraOutfitGeometry(diameter);
      final capes = outfit
          .where((i) => i.layer == WardrobeLayer.behindCharacter)
          .toList();
      final companions = outfit.where((i) => i.slot == WardrobeSlot.companion);
      return SizedBox(
        width: geometry.size.width,
        height: geometry.size.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: geometry.bodyRect,
              child: FinoraCharacter(
                size: diameter,
                moods: moods,
                rings: rings,
                behindBodyBuilder: capes.isEmpty
                    ? null
                    : (radiusScale) => IgnorePointer(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (final cape in capes)
                              Positioned.fill(
                                child: FinoraCapeLayer(
                                  item: cape,
                                  bodySize: diameter,
                                  radiusScale: radiusScale,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
            for (final item in companions)
              Positioned.fromRect(
                rect: geometry.bodyRect,
                child: _Floating(
                  amplitude: math.min(4.0, diameter * .035),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      WardrobePiece(
                        item,
                        diameter / 2,
                        scale: companionScale,
                        tilt: companionTilt,
                        sleeping: companionSleeping,
                        onTap: onCompanionTap,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// A companion gently floating up and down beside her, within reserved bounds.
class _Floating extends StatefulWidget {
  const _Floating({required this.child, required this.amplitude});
  final Widget child;
  final double amplitude;
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
      _c.value = 0;
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
      offset: Offset(0, math.sin(_c.value * 2 * math.pi) * widget.amplitude),
      child: child,
    ),
  );
}
