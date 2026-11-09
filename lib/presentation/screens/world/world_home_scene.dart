import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finora_world.dart';
import '../../../domain/wardrobe.dart';
import '../../l10n_widgets.dart';
import '../../widgets/finora_dressed.dart';
import '../../widgets/finora_orb.dart';
import '../../widgets/motion.dart';
import 'world_components.dart';

/// A real background layer, with the existing character and equipment above it.
class WorldHomeScene extends StatefulWidget {
  const WorldHomeScene({
    super.key,
    required this.world,
    required this.wardrobe,
    required this.onDecorate,
    this.onBackground,
    this.celebrating = false,
  });
  final WorldState world;
  final WardrobeState wardrobe;
  final VoidCallback onDecorate;
  final VoidCallback? onBackground;
  final bool celebrating;
  @override
  State<WorldHomeScene> createState() => _WorldHomeSceneState();
}

class _WorldHomeSceneState extends State<WorldHomeScene> {
  bool _happy = false, _sleeping = false;
  Timer? _reaction;
  void _greet() {
    _reaction?.cancel();
    setState(() {
      _happy = true;
      _sleeping = false;
    });
    _reaction = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _happy = false);
    });
  }

  @override
  void dispose() {
    _reaction?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth;
      final height = box.hasBoundedHeight ? box.maxHeight : 420.0;
      final art = WorldArt.background(widget.world.background);
      final worn = Wardrobe.worn(widget.wardrobe);
      final companion = worn
          .where((i) => i.slot == WardrobeSlot.companion)
          .firstOrNull;
      final body = math.min(150.0, math.min(width * .34, height * .35));
      final reduced = Motion.reduced(context);
      final scale = MediaQuery.textScalerOf(context).scale(1);
      return SizedBox(
        height: height,
        child: ClipRRect(
          key: const ValueKey('world-home-scene'),
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  art.asset,
                  key: ValueKey('world-background-layer-${art.id}'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  alignment: Alignment.center,
                  cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(256, 1052),
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stack) => Image.asset(
                    worldBackgroundArt.first.asset,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              // Existing decor has its own presentation; furniture inside the PNG
              // stays part of that flat image and receives no interactive hotspots.
              for (final entry in widget.world.decor.entries)
                Positioned(
                  left: entry.key == 'left' ? 14 : null,
                  right: entry.key == 'right' ? 14 : null,
                  top: entry.key == 'shelf' ? height * .28 : null,
                  bottom: entry.key == 'shelf' ? null : height * .12,
                  child: _DecorObject(id: entry.value),
                ),
              Positioned(
                left: width * .5 - body * FinoraDressed.centerX,
                top: height * .80 - body * 1.67,
                width: body * FinoraDressed.widthFactor,
                height: body * FinoraDressed.heightFactor,
                child: Semantics(
                  button: true,
                  label: 'Финора. Нажмите, чтобы поздороваться',
                  child: GestureDetector(
                    key: const ValueKey('world-finora-tap'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _greet,
                    child: AnimatedScale(
                      scale: _happy && !reduced ? 1.025 : 1,
                      duration: Duration(milliseconds: reduced ? 0 : 180),
                      child: FinoraDressed(
                        size: body,
                        outfit: worn,
                        rings: false,
                        companionScale: _happy && !reduced ? 1.1 : 1,
                        companionTilt: _happy && !reduced ? -.12 : 0,
                        companionSleeping: _sleeping,
                        onCompanionTap: _greet,
                        moods: [
                          widget.celebrating
                              ? FinoraMood.delight
                              : _sleeping
                              ? FinoraMood.sleep
                              : _happy
                              ? FinoraMood.happy
                              : FinoraMood.calm,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SceneAction(
                      key: const ValueKey('world-change-background'),
                      icon: 'background',
                      label: 'Фон',
                      onPressed: widget.onBackground ?? widget.onDecorate,
                      compact: height < 300,
                    ),
                    const SizedBox(height: 8),
                    _SceneAction(
                      key: const ValueKey('world-decorate'),
                      icon: 'decor',
                      label: 'Декор',
                      onPressed: widget.onDecorate,
                      compact: height < 300,
                    ),
                  ],
                ),
              ),
              if (widget.celebrating)
                const Positioned(
                  top: 18,
                  left: 18,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: worldJade,
                    size: 30,
                  ),
                ),
              if (companion != null)
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: WorldPearlSurface(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: TextButton.icon(
                        key: const ValueKey('world-pet-rest'),
                        onPressed: () => setState(() {
                          _sleeping = !_sleeping;
                          _happy = false;
                        }),
                        icon: Icon(
                          _sleeping
                              ? Icons.wb_sunny_outlined
                              : Icons.bedtime_outlined,
                          size: 17,
                        ),
                        label: Text(
                          _sleeping ? 'Позвать' : 'Тихий час',
                          style: TextStyle(fontSize: scale > 1.3 ? 11 : 12),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _SceneAction extends StatelessWidget {
  const _SceneAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.compact = false,
  });
  final String icon, label;
  final VoidCallback onPressed;
  final bool compact;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 44 : 56,
            height: compact ? 44 : 56,
            decoration: BoxDecoration(
              color: worldPearl.withValues(alpha: .85),
              shape: BoxShape.circle,
              border: Border.all(color: worldChampagne),
            ),
            child: WorldArtImage(icon, size: compact ? 40 : 52),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: worldPearl.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: worldChampagne),
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DecorObject extends StatelessWidget {
  const _DecorObject({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Semantics(
    label: worldCosmetic(id)?.name ?? id,
    child: WorldPearlSurface(
      padding: const EdgeInsets.all(10),
      child: Icon(worldCosmeticIcon(id), color: worldJade, size: 24),
    ),
  );
}
