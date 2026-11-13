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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Flexible(
                        child: FlowSprite(
                          'hud_level_label',
                          width: 130,
                          height: 30,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: FlowNumber(level.id, size: 30)),
                    ],
                  ),
                ),
                FlowArtButton(
                  key: const ValueKey('flow-preparation-close'),
                  art: 'map_node_available',
                  label: 'Закрыть',
                  onPressed: _busy ? null : () => Navigator.maybePop(context),
                  width: 48,
                  height: 48,
                  child: const Icon(
                    Icons.close_rounded,
                    color: flowInk,
                    size: 25,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FlowArtPanel(
              art: 'out_of_moves_button_restart_base',
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Flexible(
                    child: FlowSprite(
                      'prelevel_label_moves',
                      width: 94,
                      height: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: FlowNumber(level.moves, size: 24)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              label: 'Цели уровня',
              child: const FlowSprite('prelevel_label_goals', height: 26),
            ),
            const SizedBox(height: 10),
            FlowGoals(goals: level.goals, iconSize: 58),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(color: Color(0xFFD4B592), height: 1),
            ),
            Semantics(
              header: true,
              label: 'Усилители',
              child: const FlowSprite('prelevel_label_boosters', height: 26),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final tool in const [
                  FlowTool.bomb,
                  FlowTool.shuffle,
                  FlowTool.extraMoves,
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Semantics(
                        selected: _tools.contains(tool),
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: FlowSprite(
                                'booster_slot',
                                fit: BoxFit.fill,
                              ),
                            ),
                            if (_tools.contains(tool))
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFF4BCDA8),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FlowArtButton(
                                  key: ValueKey('flow-prelevel-${tool.name}'),
                                  art: flowToolArt(tool),
                                  label:
                                      '${flowToolName(tool)}, запас ${flow.available(tool)}',
                                  onPressed: _busy || flow.available(tool) == 0
                                      ? null
                                      : () => setState(
                                          () => _tools.contains(tool)
                                              ? _tools.remove(tool)
                                              : _tools.add(tool),
                                        ),
                                  height: 64,
                                  width: 72,
                                ),
                                SizedBox(
                                  height: 24,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: FlowNumber(
                                          flow.available(tool),
                                          size: 16,
                                        ),
                                      ),
                                      if (_tools.contains(tool))
                                        const Icon(
                                          Icons.check_circle_rounded,
                                          color: Color(0xFF27896C),
                                          size: 19,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (_tools.contains(FlowTool.bomb))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Бомба сработает в центре поля',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: flowInk, fontSize: 13),
                ),
              ),
            const SizedBox(height: 14),
            FlowArtButton(
              key: const ValueKey('flow-start'),
              art: 'victory_button_primary_base',
              labelArt: 'prelevel_label_play',
              label: _busy ? 'Сохраняем' : 'Играть',
              onPressed: _busy ? null : _start,
              width: double.infinity,
              height: 60,
            ),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              received
                  ? 'Награда первого прохождения уже получена'
                  : 'Первое прохождение: ${reward.xp} опыта и ${reward.sparks} искр',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: flowInk),
            ),
            if (level.tutorial.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  level.tutorial,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: flowInk),
                ),
              ),
          ],
        ),
      ),
    );
  }
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
            Text(
              FlowTileArt.name(type),
              style: const TextStyle(color: flowInk, fontSize: 13),
            ),
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
