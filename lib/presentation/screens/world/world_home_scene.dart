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
    this.topInset = 0,
    this.bottomInset = 0,
    this.reaction,
  });
  final WorldState world;
  final WardrobeState wardrobe;
  final VoidCallback onDecorate;
  final VoidCallback? onBackground;
  final bool celebrating;
  final double topInset, bottomInset;
  final Widget? reaction;
  @override
  State<WorldHomeScene> createState() => _WorldHomeSceneState();
}

class _WorldHomeSceneState extends State<WorldHomeScene> {
  bool _happy = false, _sleeping = false;
  Timer? _reaction, _speechTimer;
  bool _speaking = false;
  void _greet() {
    _reaction?.cancel();
    _speechTimer?.cancel();
    setState(() {
      _speaking = true;
      _happy = true;
      _sleeping = false;
    });
    _speechTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _speaking = false);
    });
    _reaction = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _happy = false);
    });
  }

  @override
  void dispose() {
    _reaction?.cancel();
    _speechTimer?.cancel();
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
      final immersive = widget.bottomInset > 0;
      final landscape = width > height;
      final ground = immersive
          ? math.min(
              height * .78,
              height - widget.bottomInset - (width > height ? 14 : 34),
            )
          : height * .80;
      final room = math.max(24.0, ground - widget.topInset);
      final body = immersive
          ? math.min(174.0, math.min(width * .43, room * .58))
          : math.min(150.0, math.min(width * .34, height * .35));
      final reduced = Motion.reduced(context);
      return SizedBox(
        height: height,
        child: ClipRRect(
          key: const ValueKey('world-home-scene'),
          borderRadius: BorderRadius.circular(immersive ? 0 : 28),
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
                  top: entry.key == 'shelf'
                      ? math.max(widget.topInset + 16, height * .32)
                      : null,
                  bottom: entry.key == 'shelf'
                      ? null
                      : height - ground + (landscape ? 6 : 64),
                  child: _DecorObject(id: entry.value),
                ),
              Positioned(
                left: width * .5 - body * FinoraDressed.centerX,
                top: ground - body * 1.67,
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
                              : FinoraMood.idle,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: widget.topInset + (landscape ? -10 : 8),
                right: MediaQuery.paddingOf(context).right + 10,
                child: Flex(
                  direction: landscape ? Axis.horizontal : Axis.vertical,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SceneAction(
                      key: const ValueKey('world-change-background'),
                      icon: 'background',
                      label: 'Фон',
                      showLabel: !landscape,
                      onPressed: widget.onBackground ?? widget.onDecorate,
                      compact:
                          height - widget.topInset - widget.bottomInset < 330,
                    ),
                    const SizedBox(height: 8, width: 8),
                    _SceneAction(
                      key: const ValueKey('world-decorate'),
                      icon: 'decor',
                      label: 'Декор',
                      showLabel: !landscape,
                      onPressed: widget.onDecorate,
                      compact:
                          height - widget.topInset - widget.bottomInset < 330,
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
              if (widget.reaction != null && (_speaking || widget.celebrating))
                Positioned(
                  top: math.max(
                    widget.topInset + 10,
                    ground - body * 1.67 - 90,
                  ),
                  left: 12 + MediaQuery.paddingOf(context).left,
                  right: 92 + MediaQuery.paddingOf(context).right,
                  child: widget.reaction!,
                ),
              if (companion != null)
                Positioned(
                  bottom: widget.bottomInset + 8,
                  left: MediaQuery.paddingOf(context).left + 68,
                  child: WorldPearlSurface(
                    padding: EdgeInsets.zero,
                    child: IconButton(
                      key: const ValueKey('world-pet-rest'),
                      tooltip: _sleeping ? 'Позвать питомца' : 'Тихий час',
                      onPressed: () => setState(() {
                        _sleeping = !_sleeping;
                        _happy = false;
                      }),
                      icon: Icon(
                        _sleeping
                            ? Icons.wb_sunny_outlined
                            : Icons.bedtime_outlined,
                        size: 22,
                        color: worldJade,
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
    this.showLabel = true,
  });
  final String icon, label;
  final VoidCallback onPressed;
  final bool compact, showLabel;
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
            width: compact ? 48 : 62,
            height: compact ? 48 : 62,
            decoration: BoxDecoration(
              color: worldPearl.withValues(alpha: .85),
              shape: BoxShape.circle,
              border: Border.all(color: worldChampagne),
            ),
            child: WorldArtImage(icon, size: compact ? 44 : 58),
          ),
          if (showLabel)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: worldPearl.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: worldChampagne),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
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
