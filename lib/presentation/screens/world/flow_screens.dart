import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../../domain/finora_world.dart';
import '../../../domain/flow/flow.dart';
import '../../../services/flow_catalog.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import 'finora_retry_dialog.dart';
import 'flow_art.dart';
import 'flow_board.dart';
import 'flow_dialogs.dart';
import 'flow_game_screen.dart';
import 'flow_hud.dart';
import 'flow_map_scene.dart';
import 'world_components.dart';

Route<void> flowPreparationRoute(
  BuildContext context,
  FlowLevel level,
  List<FlowLevel> levels, {
  VoidCallback? onExitWorld,
}) => PageRouteBuilder<void>(
  opaque: false,
  barrierDismissible: false,
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 180),
  reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 140),
  pageBuilder: (_, _, _) => WorldTheme(
    child: FlowPreparationScreen(
      level: level,
      levels: levels,
      onExitWorld: onExitWorld,
    ),
  ),
  transitionsBuilder: (_, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
);

class FlowMapScreen extends StatefulWidget {
  const FlowMapScreen({super.key, this.onExitWorld});
  final VoidCallback? onExitWorld;
  @override
  State<FlowMapScreen> createState() => _FlowMapScreenState();
}

class _FlowMapScreenState extends State<FlowMapScreen> {
  late Future<List<FlowLevel>> _levels = FlowCatalog.load();
  void _open(List<FlowLevel> levels, FlowLevel level, {bool resume = false}) {
    if (resume) {
      worldOpen(
        context,
        FlowGameScreen(
          level: level,
          levels: levels,
          onExitWorld: widget.onExitWorld,
        ),
      );
    } else {
      Navigator.of(context).push(
        flowPreparationRoute(
          context,
          level,
          levels,
          onExitWorld: widget.onExitWorld,
        ),
      );
    }
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
      final progress = FinanceScope.of(context).data.world.flow;
      final current = progress.session;
      return FlowTerraceMap(
        levels: levels,
        progress: progress,
        onBack: () => Navigator.maybePop(context),
        onOpen: (level) => _open(levels, level),
        onResume: current == null || current.finished
            ? null
            : () => _open(
                levels,
                levels.firstWhere((l) => l.id == current.levelId),
                resume: true,
              ),
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
  final Set<FlowTool> _tools = {};
  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    final c = FinanceScope.of(context);
    final old = c.data.world.flow.session;
    try {
      if (old != null && !old.finished) {
        final replace = await showFinoraRetryDialog(
          context,
          unfinishedLevel: old.levelId,
          panelAsset: 'assets/finora/match3/pause/pause_panel_base.png',
          cancelButtonAsset:
              'assets/finora/match3/victory/victory_button_secondary_base.png',
          confirmButtonAsset:
              'assets/finora/match3/victory/victory_button_primary_base.png',
        );
        if (!replace || !mounted) return;
      }
      final sparks = c.data.world.sparks;
      await c.startFlow(widget.level, restart: true, tools: _tools);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => WorldTheme(
            child: FlowGameScreen(
              level: widget.level,
              levels: widget.levels,
              onExitWorld: widget.onExitWorld,
              initialReward: c.data.world.sparks - sparks,
            ),
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
    final flow = c.data.world.flow;
    final level = widget.level;
    final received = c.data.world.rewards.containsKey(
      'flow:level:${level.id}:v1',
    );
    final reward = WorldCatalog.rewards['game']!;
    return WorldTheme(
      child: FlowOverlay(
        blur: true,
        // 1.62: the approved start card — the «Уровень» lettering with a
        // live number, the lavender «Ходы:» pill, «Цели уровня» with the
        // pieces and counts on badges, then «Усилители».
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Semantics(
                    header: true,
                    label: 'Уровень ${level.id}',
                    excludeSemantics: true,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const FlowSprite('hud_level_label', height: 32),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${level.id}',
                                textScaler: TextScaler.noScaling,
                                style: flowText(30).copyWith(height: 1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                FlowArtButton(
                  key: const ValueKey('flow-preparation-close'),
                  art: 'map_node_available',
                  label: 'Закрыть',
                  onPressed: _busy ? null : () => Navigator.maybePop(context),
                  width: 48,
                  height: 48,
                  visualSize: 36,
                  child: const Icon(
                    Icons.close_rounded,
                    color: flowInk,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Ходы: ${level.moves}',
              excludeSemantics: true,
              child: SizedBox(
                key: const ValueKey('flow-prelevel-moves'),
                width: 168,
                height: 40,
                child: FlowArtPanel(
                  art: 'out_of_moves_button_restart_base',
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const FlowSprite('prelevel_label_moves', height: 22),
                          const SizedBox(width: 5),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '${level.moves}',
                              textScaler: TextScaler.noScaling,
                              style: flowText(
                                19,
                                color: _number,
                              ).copyWith(height: 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              label: 'Цели уровня',
              child: const FlowSprite('prelevel_label_goals', height: 22),
            ),
            const SizedBox(height: 8),
            _PrelevelGoals(goals: level.goals),
            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 1, color: Color(0x66C9A46A)),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              label: 'Усилители',
              child: const FlowSprite('prelevel_label_boosters', height: 22),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final tool in const [
                  FlowTool.bomb,
                  FlowTool.shuffle,
                  FlowTool.extraMoves,
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Semantics(
                        selected: _tools.contains(tool),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: FlowToolTile(
                            tool: tool,
                            stock: flow.available(tool),
                            selected: _tools.contains(tool),
                            buttonKey: ValueKey('flow-prelevel-${tool.name}'),
                            onPressed: _busy || flow.available(tool) == 0
                                ? null
                                : () => setState(
                                    () => _tools.contains(tool)
                                        ? _tools.remove(tool)
                                        : _tools.add(tool),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (_tools.contains(FlowTool.bomb))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Бомба сработает в центре поля',
                  textAlign: TextAlign.center,
                  style: flowText(12, bold: false),
                ),
              ),
            const SizedBox(height: 14),
            FlowArtButton(
              key: const ValueKey('flow-start'),
              art: 'victory_button_primary_base',
              label: _busy ? 'Сохраняем' : 'Играть',
              onPressed: _busy ? null : _start,
              width: double.infinity,
              height: 56,
              // 1.62: the pack's «Играть» lettering; live text while saving.
              labelArt: _busy ? null : 'prelevel_label_play',
              child: _busy ? Text('Сохраняем', style: flowText(19)) : null,
            ),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 10),
            Text(
              received
                  ? 'Награда первого прохождения уже получена'
                  : 'Первое прохождение: ${reward.xp} опыта и ${reward.sparks} искр',
              textAlign: TextAlign.center,
              style: flowText(12, color: flowInk.withValues(alpha: .75)),
            ),
            if (level.tutorial.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  level.tutorial,
                  textAlign: TextAlign.center,
                  style: flowText(12, bold: false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const _number = Color(0xFF610738);

/// The level's goals: the approved pieces in an even row, each count on the
/// pack's empty badge, all numbers at one size and baseline.
class _PrelevelGoals extends StatelessWidget {
  const _PrelevelGoals({required this.goals});
  final List<FlowGoal> goals;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final perRow = math.min(3, math.max(1, goals.length));
      final cell = math.min(96.0, box.maxWidth / perRow);
      return Wrap(
        alignment: WrapAlignment.center,
        runSpacing: 8,
        children: [
          for (final goal in goals)
            SizedBox(
              width: cell,
              child: Semantics(
                label: '${goal.title}: ${goal.target}',
                excludeSemantics: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FlowGoalIcon(goal.key, size: cell * .62),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: cell * .68,
                      height: cell * .68 / 1.85,
                      child: Stack(
                        children: [
                          const Positioned.fill(
                            child: FlowSprite('booster_counter_badge'),
                          ),
                          Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: cell * .1,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  flowNumber(goal.target),
                                  textScaler: TextScaler.noScaling,
                                  style: flowText(cell * .2, color: _number),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class FlowLegend extends StatelessWidget {
  const FlowLegend({super.key, required this.types});
  final List<FlowTile> types;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: [
      for (final type in types)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowSprite(
              'match3_${type.name}',
              width: 28,
              height: 28,
              trim: false,
            ),
            Text(FlowTileArt.name(type), style: flowText(13, bold: false)),
          ],
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
          FlowSprite(
            i < stars ? 'map_star_earned' : 'map_star_empty',
            width: 22,
            height: 22,
          ),
      ],
    ),
  );
}
