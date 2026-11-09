import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/motion.dart';

/// Source files remain complete square PNGs, including their transparent rim.
/// These are display coordinates, never another copy of a goal's savings.
abstract final class WorldGardenArt {
  static const background =
      'assets/finora/world/garden/background/goal_garden.png';
  static const stages = [
    'assets/finora/world/garden/stages/01_seed.png',
    'assets/finora/world/garden/stages/02_sprout.png',
    'assets/finora/world/garden/stages/03_leaves.png',
    'assets/finora/world/garden/stages/04_bud.png',
    'assets/finora/world/garden/stages/05_opening.png',
    'assets/finora/world/garden/stages/06_full_bloom.png',
  ];
  static const names = [
    'Семечко',
    'Росток',
    'Листья',
    'Закрытый бутон',
    'Начало цветения',
    'Полное цветение',
  ];
}

/// The identical source anchor and image rectangle apply to all six stages.
/// Landscape caps the complete square by height, rather than trimming the plant.
@immutable
class WorldGardenGeometry {
  const WorldGardenGeometry(this.scene);
  final Size scene;
  static const sourceGroundAnchor = Offset(.493, .965);
  static const sceneGroundAnchor = Offset(.5, .82);

  double get spriteSize => math.min(scene.width * .76, scene.height * .78);
  Offset get ground => Offset(
    scene.width * sceneGroundAnchor.dx,
    scene.height * sceneGroundAnchor.dy,
  );
  Rect get spriteRect => Rect.fromLTWH(
    ground.dx - sourceGroundAnchor.dx * spriteSize,
    ground.dy - sourceGroundAnchor.dy * spriteSize,
    spriteSize,
    spriteSize,
  );
}

String worldGardenPercent(double ratio) {
  if (!ratio.isFinite || ratio <= 0) return '0%';
  if (ratio >= 1) return '100%';
  final percent = (ratio * 1000).floor() / 10;
  if (percent == 0) return '<0,1%';
  final number = percent == percent.floorToDouble()
      ? percent.toInt().toString()
      : percent.toStringAsFixed(1).replaceFirst('.', ',');
  return '$number%';
}

/// A single selected goal's plant on the supplied garden background.
/// No repainting, source cropping, tinted filters, extra pot or particle loop.
class WorldGardenScene extends StatelessWidget {
  const WorldGardenScene({
    super.key,
    required this.stage,
    required this.semanticLabel,
    this.onTap,
  });
  final int stage;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visualStage = stage.clamp(0, WorldGardenArt.stages.length - 1);
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: LayoutBuilder(
            builder: (context, box) {
              final height = math
                  .min(
                    box.maxWidth * 1.5,
                    MediaQuery.sizeOf(context).height * .57,
                  )
                  .clamp(260.0, 540.0);
              final size = Size(box.maxWidth, height);
              final geometry = WorldGardenGeometry(size);
              final dpr = MediaQuery.devicePixelRatioOf(context);
              final backgroundWidth = math.max(
                size.width,
                size.height * 941 / 1672,
              );
              final spriteCacheWidth = (geometry.spriteSize * dpr).ceil().clamp(
                1,
                1254,
              );
              return SizedBox(
                key: const ValueKey('world-garden-scene'),
                width: size.width,
                height: size.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        WorldGardenArt.background,
                        key: const ValueKey('world-garden-background'),
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        cacheWidth: (backgroundWidth * dpr).ceil().clamp(
                          1,
                          941,
                        ),
                        filterQuality: FilterQuality.high,
                        excludeFromSemantics: true,
                      ),
                    ),
                    Positioned.fromRect(
                      rect: geometry.spriteRect,
                      child: AnimatedSwitcher(
                        duration: Motion.reduced(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: Image.asset(
                          WorldGardenArt.stages[visualStage],
                          key: ValueKey(
                            'world-garden-sprite-stage-$visualStage',
                          ),
                          fit: BoxFit.contain,
                          width: geometry.spriteSize,
                          height: geometry.spriteSize,
                          cacheWidth: spriteCacheWidth,
                          filterQuality: FilterQuality.high,
                          isAntiAlias: true,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
