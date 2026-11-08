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

/// Only the home scene has ambient motion. Its route controls TickerMode.
class WorldHomeScene extends StatefulWidget {
  const WorldHomeScene({
    super.key,
    required this.world,
    required this.wardrobe,
    required this.onDecorate,
    this.celebrating = false,
  });
  final WorldState world;
  final WardrobeState wardrobe;
  final VoidCallback onDecorate;
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final tint = Color(
      worldCosmetic(widget.world.background)?.color ?? 0xFF9DE5C7,
    );
    final base = Color.lerp(theme.colorScheme.surface, tint, dark ? .12 : .18)!;
    final worn = Wardrobe.worn(widget.wardrobe);
    final companion = worn
        .where((item) => item.slot == WardrobeSlot.companion)
        .firstOrNull;
    final reduced = Motion.reduced(context);
    return Container(
      key: const ValueKey('world-home-scene'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: tint.withValues(alpha: .35)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Дом Финоры', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  key: const ValueKey('world-decorate'),
                  tooltip: 'Оформить дом',
                  onPressed: widget.onDecorate,
                  icon: const Icon(Icons.tune_rounded, size: 21),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, box) {
              final body = math.min(114.0, box.maxWidth / 2.7);
              final sceneHeight = body * FinoraDressed.heightFactor + 12;
              return SizedBox(
                height: sceneHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _HomeLight(tint: tint, dark: dark),
                      ),
                    ),
                    for (final e in widget.world.decor.entries)
                      Positioned(
                        left: e.key == 'left' ? 13 : null,
                        right: e.key == 'right' ? 13 : null,
                        top: e.key == 'shelf' ? 4 : null,
                        bottom: e.key == 'shelf' ? null : 14,
                        child: _DecorObject(id: e.value, tint: tint),
                      ),
                    Semantics(
                      button: true,
                      label: companion == null
                          ? 'Финора. Нажмите, чтобы поздороваться'
                          : 'Финора и ${companion.name}. Нажмите, чтобы поиграть',
                      child: GestureDetector(
                        key: const ValueKey('world-finora-tap'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _greet,
                        child: AnimatedScale(
                          scale: _happy && !reduced ? 1.025 : 1,
                          duration: Duration(milliseconds: reduced ? 0 : 250),
                          child: FinoraDressed(
                            size: body,
                            outfit: worn,
                            rings: false,
                            companionScale: _happy && !reduced ? 1.1 : 1,
                            companionTilt: _happy && !reduced ? -.12 : 0,
                            companionSleeping: _sleeping,
                            onCompanionTap: _greet,
                            moods: [
                              if (widget.celebrating)
                                FinoraMood.delight
                              else if (_sleeping)
                                FinoraMood.sleep
                              else if (_happy)
                                FinoraMood.happy
                              else
                                FinoraMood.calm,
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (widget.celebrating)
                      const Positioned(
                        top: 10,
                        right: 22,
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: worldMint,
                          size: 28,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          if (companion != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.center,
                children: [
                  Text(companion.name, style: theme.textTheme.labelMedium),
                  TextButton.icon(
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
                    label: Text(_sleeping ? 'Позвать' : 'Тихий час'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DecorObject extends StatelessWidget {
  const _DecorObject({required this.id, required this.tint});
  final String id;
  final Color tint;

  @override
  Widget build(BuildContext context) => Semantics(
    label: worldCosmetic(id)?.name ?? id,
    child: Container(
      width: 48,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: .2),
            tint.withValues(alpha: .06),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .26)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(worldCosmeticIcon(id), color: tint, size: 27),
    ),
  );
}

class _HomeLight extends CustomPainter {
  const _HomeLight({required this.tint, required this.dark});
  final Color tint;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .54);
    final glow = Rect.fromCircle(center: center, radius: size.width * .55);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            tint.withValues(alpha: dark ? .17 : .28),
            tint.withValues(alpha: 0),
          ],
        ).createShader(glow),
    );
    final floor = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * .88),
      width: size.width * .69,
      height: size.height * .11,
    );
    canvas.drawOval(floor, Paint()..color = tint.withValues(alpha: .08));
    canvas.drawOval(
      floor,
      Paint()
        ..color = Colors.white.withValues(alpha: dark ? .16 : .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final lines = Paint()
      ..color = tint.withValues(alpha: .12)
      ..strokeWidth = .8;
    canvas.drawLine(
      Offset(20, size.height * .29),
      Offset(size.width - 20, size.height * .29),
      lines,
    );
    for (final spot in const [
      Offset(.15, .19),
      Offset(.81, .12),
      Offset(.66, .29),
    ]) {
      canvas.drawCircle(
        Offset(size.width * spot.dx, size.height * spot.dy),
        2,
        Paint()..color = tint.withValues(alpha: .7),
      );
    }
  }

  @override
  bool shouldRepaint(_HomeLight oldDelegate) =>
      oldDelegate.tint != tint || oldDelegate.dark != dark;
}
