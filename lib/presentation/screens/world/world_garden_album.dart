import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finora_world.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import '../achievements_screen.dart';
import '../management.dart';
import 'world_components.dart';
import 'world_garden_scene.dart';

export 'world_garden_scene.dart';

/// One selected live financial goal, with one plant on the supplied scene.
class WorldGardenScreen extends StatefulWidget {
  const WorldGardenScreen({super.key});

  @override
  State<WorldGardenScreen> createState() => _WorldGardenScreenState();
}

class _WorldGardenScreenState extends State<WorldGardenScreen> {
  String? _scheduledGoal;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = FinanceScope.of(context);
    final first = c.data.goals.firstOrNull;
    if (c.data.world.gardenGoalId == null &&
        first != null &&
        _scheduledGoal != first.id) {
      _scheduledGoal = first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await worldAttempt(context, () => c.selectWorldGardenGoal(first.id));
        _scheduledGoal = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final goals = c.data.goals;
    final selected =
        goals.where((g) => g.id == c.data.world.gardenGoalId).firstOrNull ??
        goals.firstOrNull;
    final plant = selected == null
        ? null
        : WorldPlant.of(selected, c.data.entries);
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
        if (selected == null || plant == null) ...[
          const EmptyState(
            'Здесь вырастут ваши мечты',
            'Растение появляется вместе с финансовой целью. Рост зависит от процента накоплений.',
            icon: Icons.spa_outlined,
          ),
          FilledButton.tonal(
            key: const ValueKey('world-garden-create-goal'),
            onPressed: () => worldOpen(context, const GoalsScreen()),
            child: const Text('Создать цель'),
          ),
        ] else ...[
          WorldPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ваша цель',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                DropdownButton<String>(
                  key: const ValueKey('world-garden-goal-selector'),
                  value: selected.id,
                  isExpanded: true,
                  itemHeight: null,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final goal in goals)
                      DropdownMenuItem(
                        value: goal.id,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            goal.name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (id) =>
                      worldAttempt(context, () => c.selectWorldGardenGoal(id)),
                ),
              ],
            ),
          ),
          WorldGardenScene(
            stage: plant.visualStage,
            semanticLabel:
                '${selected.name}. ${WorldGardenArt.names[plant.visualStage]}, ${worldGardenPercent(plant.ratio)}',
            onTap: () =>
                worldOpen(context, GoalsScreen(initialGoalId: selected.id)),
          ),
          const SizedBox(height: 14),
          WorldPanel(
            key: ValueKey('world-plant-${selected.id}'),
            onTap: () =>
                worldOpen(context, GoalsScreen(initialGoalId: selected.id)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                const SizedBox(height: 8),
                Text(WorldGardenArt.names[plant.visualStage]),
                const SizedBox(height: 6),
                Text(
                  '${money(plant.savedMinor, selected.currency)} / ${money(selected.targetMinor, selected.currency)}',
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: plant.ratio,
                  color: worldMint,
                  backgroundColor: worldMint.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(8),
                  minHeight: 5,
                ),
                const SizedBox(height: 7),
                Text('${worldGardenPercent(plant.ratio)} накоплено'),
                if (selected.targetMinor <= 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Text(
                      'Укажите положительную сумму в настройках цели',
                    ),
                  ),
                if (c.data.world.completedGoals.contains(selected.id))
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Text('Момент достижения сохранён в альбоме'),
                  ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                worldOpen(context, GoalsScreen(initialGoalId: selected.id)),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Открыть цель'),
          ),
        ],
      ],
    );
  }
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
