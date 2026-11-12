import 'package:flutter/material.dart' hide Text;

import '../../../domain/finora_world.dart';
import '../../../domain/flow/flow.dart';
import '../../../services/flow_catalog.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import 'flow_board.dart';
import 'flow_game_screen.dart';
import 'world_components.dart';

class FlowMapScreen extends StatefulWidget {
  const FlowMapScreen({super.key, this.onExitWorld});
  final VoidCallback? onExitWorld;
  @override
  State<FlowMapScreen> createState() => _FlowMapScreenState();
}

class _FlowMapScreenState extends State<FlowMapScreen> {
  late Future<List<FlowLevel>> _levels = FlowCatalog.load();
  void _open(List<FlowLevel> levels, FlowLevel level, {bool resume = false}) {
    worldOpen(
      context,
      resume
          ? FlowGameScreen(
              level: level,
              levels: levels,
              onExitWorld: widget.onExitWorld,
            )
          : FlowPreparationScreen(
              level: level,
              levels: levels,
              onExitWorld: widget.onExitWorld,
            ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<FlowLevel>>(
    future: _levels,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return WorldPage(
          title: 'Finora — Поток',
          children: [
            const EmptyState(
              'Уровни не загрузились',
              'Попробуйте открыть игру ещё раз.',
            ),
            FilledButton(
              onPressed: () => setState(() => _levels = FlowCatalog.load()),
              child: const Text('Повторить'),
            ),
          ],
        );
      }
      final levels = snapshot.data;
      if (levels == null) {
        return const WorldPage(
          title: 'Finora — Поток',
          children: [
            Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        );
      }
      final c = FinanceScope.of(context);
      final progress = c.data.world.flow;
      final current = progress.session;
      return WorldPage(
        title: 'Finora — Поток',
        children: [
          Text('Первые шаги', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Пройдено ${progress.results.length} из ${levels.length}'),
          if (current != null && !current.finished) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const ValueKey('flow-resume'),
              onPressed: () => _open(
                levels,
                levels.firstWhere((l) => l.id == current.levelId),
                resume: true,
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('Продолжить уровень ${current.levelId}'),
            ),
          ],
          const SizedBox(height: 16),
          for (final level in levels)
            Builder(
              builder: (context) {
                final result = progress.results[level.id];
                final unlocked = progress.isUnlocked(level.id);
                return WorldPanel(
                  child: ListTile(
                    key: ValueKey('flow-level-${level.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: unlocked
                          ? const Color(0xFFB8DDCA)
                          : const Color(0xFFE4DEE5),
                      child: Text(
                        '${level.id}',
                        style: const TextStyle(
                          color: worldPlum,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(level.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (result != null) ...[
                          FlowStars(stars: result.stars),
                          Text('Лучший счёт: ${result.bestScore}'),
                        ] else
                          Text(
                            unlocked
                                ? '${level.moves} ходов'
                                : 'Пройдите уровень ${level.id - 1}',
                          ),
                      ],
                    ),
                    trailing: Icon(
                      unlocked ? Icons.chevron_right : Icons.lock_outline,
                    ),
                    enabled: unlocked,
                    onTap: unlocked ? () => _open(levels, level) : null,
                  ),
                );
              },
            ),
        ],
      );
    },
  );
}

class FlowPreparationScreen extends StatefulWidget {
  const FlowPreparationScreen({
    super.key,
    required this.level,
    required this.levels,
    this.onExitWorld,
  });
  final FlowLevel level;
  final List<FlowLevel> levels;
  final VoidCallback? onExitWorld;
  @override
  State<FlowPreparationScreen> createState() => _FlowPreparationScreenState();
}

class _FlowPreparationScreenState extends State<FlowPreparationScreen> {
  bool _busy = false;
  Future<void> _start() async {
    if (_busy) return;
    final c = FinanceScope.of(context);
    final old = c.data.world.flow.session;
    if (old != null && !old.finished) {
      final replace = await confirm(
        context,
        'Начать новую попытку?',
        'Незавершённая попытка уровня ${old.levelId} будет заменена. Полученные звёзды и награды сохранятся.',
      );
      if (!replace || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await c.startFlow(widget.level, restart: true);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => FlowGameScreen(
            level: widget.level,
            levels: widget.levels,
            onExitWorld: widget.onExitWorld,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final level = widget.level;
    final received = c.data.world.rewards.containsKey(
      'flow:level:${level.id}:v1',
    );
    final reward = WorldCatalog.rewards['game']!;
    return WorldPage(
      title: 'Уровень ${level.id}',
      children: [
        Text(level.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        WorldPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${level.moves} ходов',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              for (final goal in level.goals)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('${goal.title}: ${goal.target}'),
                ),
            ],
          ),
        ),
        if (level.tutorial.isNotEmpty) WorldPanel(child: Text(level.tutorial)),
        const Text(
          'Нажмите на две соседние клетки или смахните фишку в сторону. Обмен без совпадения не расходует ход.',
        ),
        const SizedBox(height: 12),
        FlowLegend(types: level.types),
        const SizedBox(height: 16),
        Text(
          received
              ? 'Награда первого прохождения уже получена.'
              : 'За первое прохождение: ${reward.xp} опыта и ${reward.sparks} искр.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('flow-start'),
          onPressed: _busy ? null : _start,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(_busy ? 'Сохраняем…' : 'Играть'),
        ),
      ],
    );
  }
}

class FlowLegend extends StatelessWidget {
  const FlowLegend({super.key, required this.types});
  final List<FlowTile> types;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 7,
    children: [
      for (final type in types)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: FlowTileArt.color(type).withValues(alpha: .5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${FlowTileArt.symbol(type)} · ${FlowTileArt.name(type)}',
            style: const TextStyle(fontSize: 12, color: worldPlum),
          ),
        ),
    ],
  );
}

class FlowStars extends StatelessWidget {
  const FlowStars({super.key, required this.stars});
  final int stars;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Звёзд: $stars из 3',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Icon(
            i < stars ? Icons.star_rounded : Icons.star_border_rounded,
            color: i < stars
                ? const Color(0xFF936521)
                : const Color(0xFF9B909C),
            size: 21,
          ),
      ],
    ),
  );
}
