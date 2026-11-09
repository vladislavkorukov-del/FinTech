import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../../domain/flow/flow.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import 'flow_board.dart';
import 'flow_screens.dart';
import 'world_components.dart';

class FlowGameScreen extends StatefulWidget {
  const FlowGameScreen({
    super.key,
    required this.level,
    required this.levels,
    this.onExitWorld,
  });
  final FlowLevel level;
  final List<FlowLevel> levels;
  final VoidCallback? onExitWorld;
  @override
  State<FlowGameScreen> createState() => _FlowGameScreenState();
}

class _FlowGameScreenState extends State<FlowGameScreen>
    with WidgetsBindingObserver {
  int? _selected;
  bool _busy = false, _paused = false;
  String? _feedback;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _paused = state != AppLifecycleState.resumed);
  }

  void _select(int cell) {
    if (_busy || _paused) return;
    final session = FinanceScope.of(context).data.world.flow.session;
    if (session == null || session.finished) return;
    if (!session.board[cell].movable) {
      setState(() => _feedback = 'Эта клетка пока заблокирована');
      return;
    }
    final previous = _selected;
    if (previous == null || !FlowEngine.neighbors(previous, cell)) {
      setState(() => _selected = previous == cell ? null : cell);
    } else {
      _exchange(previous, cell);
    }
  }

  Future<void> _exchange(int from, int to) async {
    if (_busy || _paused) return;
    final c = FinanceScope.of(context);
    final session = c.data.world.flow.session;
    if (session == null || session.finished) return;
    setState(() {
      _busy = true;
      _selected = null;
      _feedback = null;
    });
    try {
      final turn = await c.swapFlow(widget.level, session, from, to);
      if (mounted) {
        setState(
          () => _feedback = turn.accepted
              ? turn.shuffled
                    ? 'Поле перемешано. Ход не потрачен на перемешивание.'
                    : null
              : 'Нет совпадения — ход сохранён',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replay() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await FinanceScope.of(context).startFlow(widget.level, restart: true);
      if (mounted) {
        setState(() {
          _selected = null;
          _feedback = null;
        });
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final session = c.data.world.flow.session;
    final level = widget.level;
    if (session == null || session.levelId != level.id) {
      return WorldPage(
        title: 'Finora — Поток',
        children: [
          const EmptyState(
            'Попытка недоступна',
            'Выберите уровень, чтобы начать игру.',
          ),
          FilledButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('К уровням'),
          ),
        ],
      );
    }
    if (session.finished) return _result(context, session);
    return WorldPage(
      title: 'Уровень ${level.id}',
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            WorldStat(
              icon: Icons.touch_app_outlined,
              text: 'Ходы: ${session.remainingMoves}',
            ),
            WorldStat(icon: Icons.star_outline, text: 'Счёт: ${session.score}'),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final goal in level.goals)
              WorldStat(
                icon: Icons.flag_outlined,
                text:
                    '${goal.title}: ${math.min(goal.target, session.progress[goal.key] ?? 0)}/${goal.target}',
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_paused)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Пауза. Ходы сохранены.'),
          ),
        WorldPanel(
          child: FlowBoard(
            session: session,
            selected: _selected,
            enabled: !_busy && !_paused,
            onSelect: _select,
            onExchange: _exchange,
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_feedback != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_feedback!),
          ),
        if (level.teachingMove != null && session.remainingMoves == level.moves)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Учебный ход: ${_position(level.teachingMove!.$1)} на ${_position(level.teachingMove!.$2)}',
            ),
          ),
        const Text(
          'Две соседние клетки — обмен. I — слой льда, R с числом — стопка чеков.',
        ),
        const SizedBox(height: 10),
        FlowLegend(types: level.types),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.map_outlined),
          label: const Text('К уровням'),
        ),
      ],
    );
  }

  String _position(int index) => '${index ~/ 8 + 1}:${index % 8 + 1}';

  Widget _result(BuildContext context, FlowSession session) {
    final c = FinanceScope.of(context);
    final won = session.status == FlowStatus.won;
    final next = widget.levels
        .where((l) => l.id == widget.level.id + 1)
        .firstOrNull;
    return WorldPage(
      title: won ? 'Уровень пройден' : 'Попробуем ещё?',
      children: [
        WorldPanel(
          key: const ValueKey('flow-result'),
          child: Column(
            children: [
              Icon(
                won ? Icons.check_circle_outline : Icons.refresh_rounded,
                color: worldJade,
                size: 42,
              ),
              const SizedBox(height: 12),
              Text(
                won
                    ? 'Уровень ${widget.level.id} завершён'
                    : 'Ходы закончились',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              if (won) FlowStars(stars: session.stars(widget.level)),
              Text('Счёт: ${session.score}'),
              if (won)
                Text(
                  'Лучший счёт: ${c.data.world.flow.results[widget.level.id]?.bestScore ?? session.score}',
                ),
              const SizedBox(height: 8),
              for (final goal in widget.level.goals)
                Text(
                  '${goal.title}: ${math.min(goal.target, session.progress[goal.key] ?? 0)}/${goal.target}',
                ),
              if (won)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Награда первого прохождения сохранена. Повтор не начисляет её снова.',
                  ),
                ),
            ],
          ),
        ),
        if (won && next != null && c.data.world.flow.isUnlocked(next.id))
          FilledButton.icon(
            key: const ValueKey('flow-next'),
            onPressed: () => Navigator.of(context).pushReplacement<void, void>(
              MaterialPageRoute(
                builder: (_) => FlowPreparationScreen(
                  level: next,
                  levels: widget.levels,
                  onExitWorld: widget.onExitWorld,
                ),
              ),
            ),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Следующий уровень'),
          ),
        if (won && next == null) const Text('Все 20 уровней пройдены'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('flow-replay'),
          onPressed: _busy ? null : _replay,
          icon: const Icon(Icons.replay),
          label: const Text('Повторить уровень'),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('flow-map'),
          onPressed: () => Navigator.maybePop(context),
          child: const Text('К уровням'),
        ),
        if (widget.onExitWorld != null)
          TextButton(
            key: const ValueKey('flow-exit-world'),
            onPressed: widget.onExitWorld,
            child: const Text('В Мир Финоры'),
          ),
      ],
    );
  }
}
