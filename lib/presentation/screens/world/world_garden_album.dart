import 'dart:math' as math;

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finora_world.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import '../achievements_screen.dart';
import '../management.dart';
import 'world_components.dart';

class WorldGardenScreen extends StatelessWidget {
  const WorldGardenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    return WorldPage(
      title: 'Сад целей',
      actions: [
        IconButton(
          tooltip: 'Открыть мечты',
          onPressed: () => worldOpen(context, const GoalsScreen()),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      children: [
        if (c.data.goals.isEmpty) ...[
          const EmptyState(
            'Здесь вырастут ваши мечты',
            'Растение появляется вместе с финансовой целью. Рост зависит от процента накоплений.',
            icon: Icons.spa_outlined,
          ),
          FilledButton.tonal(
            onPressed: () => worldOpen(context, const GoalsScreen()),
            child: const Text('Создать цель'),
          ),
        ],
        for (final goal in c.data.goals)
          Builder(
            builder: (context) {
              final plant = WorldPlant.of(goal, c.data.entries);
              final complete = c.data.world.completedGoals.contains(goal.id);
              return WorldPanel(
                key: ValueKey('world-plant-${goal.id}'),
                onTap: () =>
                    worldOpen(context, GoalsScreen(initialGoalId: goal.id)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Semantics(
                          label:
                              '${plant.stageName}, ${(plant.ratio * 100).round()}%',
                          child: SizedBox(
                            width: 82,
                            height: 96,
                            child: CustomPaint(
                              painter: WorldPlantPainter(
                                stage: plant.stage,
                                color: Color(goal.color),
                                commemorated: complete,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                goal.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(plant.stageName),
                              const SizedBox(height: 4),
                              Text(
                                '${money(plant.savedMinor, goal.currency)} / ${money(goal.targetMinor, goal.currency)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 20),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: plant.ratio,
                      color: worldMint,
                      backgroundColor: worldMint.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(8),
                      minHeight: 5,
                    ),
                    const SizedBox(height: 7),
                    Text('${(plant.ratio * 100).round()}% накоплено'),
                    if (complete)
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Text('Момент достижения сохранён в альбоме'),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Small vector plants share their geometry at every savings amount.
/// Completed memories are retained; no wilted or punishing state exists.
class WorldPlantPainter extends CustomPainter {
  const WorldPlantPainter({
    required this.stage,
    required this.color,
    this.commemorated = false,
  });
  final int stage;
  final Color color;
  final bool commemorated;

  @override
  void paint(Canvas canvas, Size size) {
    final pot = Rect.fromLTWH(
      size.width * .25,
      size.height * .69,
      size.width * .5,
      size.height * .23,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pot, const Radius.circular(10)),
      Paint()..color = color.withValues(alpha: .17),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pot, const Radius.circular(10)),
      Paint()
        ..color = color.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final soil = Offset(size.width / 2, size.height * .7);
    if (stage == 0) {
      canvas.drawOval(
        Rect.fromCenter(
          center: soil - const Offset(0, 4),
          width: 10,
          height: 7,
        ),
        Paint()..color = color,
      );
      return;
    }
    final top = Offset(size.width / 2, size.height * (stage >= 3 ? .22 : .36));
    final stem = Paint()
      ..color = Color.lerp(color, worldMint, .7)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(soil.dx, soil.dy)
      ..quadraticBezierTo(soil.dx - 4, size.height * .47, top.dx, top.dy);
    canvas.drawPath(path, stem);
    for (var i = 0; i < (stage >= 2 ? 2 : 1); i++) {
      final y = size.height * (.51 - i * .16);
      final direction = i.isEven ? -1 : 1;
      final leaf = Path()
        ..moveTo(size.width / 2, y + 8)
        ..quadraticBezierTo(
          size.width / 2 + 26 * direction,
          y + 2,
          size.width / 2 + 19 * direction,
          y - 10,
        )
        ..quadraticBezierTo(
          size.width / 2 + 2 * direction,
          y - 11,
          size.width / 2,
          y + 8,
        );
      canvas.drawPath(
        leaf,
        Paint()
          ..color = Color.lerp(color, worldMint, .5)!.withValues(alpha: .75),
      );
    }
    if (stage >= 3) {
      final petals = stage == 4 ? 5 : 1;
      for (var i = 0; i < petals; i++) {
        final angle = math.pi * 2 * i / petals - math.pi / 2;
        final center =
            top +
            Offset(math.cos(angle), math.sin(angle)) * (stage == 4 ? 9 : 2);
        canvas.drawCircle(
          center,
          stage == 4 ? 8 : 6,
          Paint()..color = Color.lerp(color, Colors.white, .38)!,
        );
      }
      canvas.drawCircle(
        top,
        stage == 4 ? 5 : 3,
        Paint()..color = const Color(0xFFF0D997),
      );
    }
    if (commemorated) {
      canvas.drawCircle(
        Offset(size.width * .82, size.height * .18),
        3,
        Paint()..color = worldMint,
      );
    }
  }

  @override
  bool shouldRepaint(WorldPlantPainter oldDelegate) =>
      oldDelegate.stage != stage ||
      oldDelegate.color != color ||
      oldDelegate.commemorated != commemorated;
}

class WorldAlbumScreen extends StatelessWidget {
  const WorldAlbumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final state = c.data.world;
    final memories = state.memories.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return WorldPage(
      title: 'Альбом воспоминаний',
      children: [
        WorldPanel(
          child: SwitchListTile.adaptive(
            key: const ValueKey('world-album-privacy'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Скрывать личные сведения'),
            subtitle: const Text('Названия целей и суммы в карточках альбома'),
            value: state.hidePrivate,
            onChanged: (value) => worldAttempt(
              context,
              () => c.worldSettings(hidePrivate: value),
            ),
          ),
        ),
        if (memories.isEmpty)
          const EmptyState(
            'Альбом пока пуст',
            'Выберите питомца, оформите дом или достигните цели — момент сохранится здесь.',
          ),
        for (final memory in memories)
          Builder(
            builder: (context) {
              final card = memory.toJson(hidePrivate: state.hidePrivate);
              return WorldPanel(
                key: ValueKey('world-memory-${memory.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 70,
                          height: 78,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: worldMint.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: memory.asset == null
                              ? const Icon(
                                  Icons.auto_awesome_outlined,
                                  color: worldMint,
                                )
                              : Image.asset(
                                  memory.asset!,
                                  fit: BoxFit.contain,
                                  cacheWidth: 210,
                                  filterQuality: FilterQuality.high,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card['title']! as String,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                displayDate(memory.date),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Text(card['description']! as String),
                              if (!state.hidePrivate &&
                                  memory.amountMinor != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    money(
                                      memory.amountMinor!,
                                      memory.currency ?? c.currency,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (memory.goalId != null && c.goal(memory.goalId) != null)
                      TextButton(
                        onPressed: () => worldOpen(
                          context,
                          GoalsScreen(initialGoalId: memory.goalId),
                        ),
                        child: const Text('Открыть цель'),
                      ),
                  ],
                ),
              );
            },
          ),
        OutlinedButton.icon(
          onPressed: () => worldOpen(context, const AchievementsScreen()),
          icon: const Icon(Icons.emoji_events_outlined),
          label: const Text('Все достижения'),
        ),
      ],
    );
  }
}
