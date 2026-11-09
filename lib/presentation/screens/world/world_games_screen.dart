import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finora_world.dart';
import '../../../domain/world_games.dart';
import '../../controller.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import 'world_components.dart';
import 'flow_screens.dart';

/// All three activities live inside the world; they never navigate through or
/// modify a financial form. Every successful move is committed before advancing.
class WorldGamesScreen extends StatelessWidget {
  const WorldGamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Игры и путешествия')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SurfaceCard(
            key: const ValueKey('world-game-flow'),
            onTap: () {
              final navigator = Navigator.of(context);
              final gamesRoute = ModalRoute.of(context);
              worldOpen(
                context,
                FlowMapScreen(
                  onExitWorld: () {
                    navigator.popUntil((route) => identical(route, gamesRoute));
                    if (gamesRoute != null && !gamesRoute.isFirst) {
                      navigator.pop();
                    }
                  },
                ),
              );
            },
            child: Row(
              children: [
                Image.asset(
                  'assets/finora/world/ui/png/games.png',
                  width: 64,
                  height: 64,
                  fit: BoxFit.contain,
                  cacheWidth: 192,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Finora — Поток',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text('3 в ряд · 20 уровней'),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Каждая активность даёт награду один раз. Можно возвращаться и играть без дополнительных наград.',
          ),
          const SizedBox(height: 16),
          for (final kind in WorldGames.kinds)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        WorldGames.title(kind),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    for (var level = 0; level < WorldGames.levels; level++)
                      _LevelTile(kind: kind, level: level, c: c),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({required this.kind, required this.level, required this.c});
  final String kind;
  final int level;
  final FinanceController c;

  @override
  Widget build(BuildContext context) {
    final key = '$kind:$level';
    final moves = c.data.world.games[key] ?? const <int>[];
    final done = WorldGames.complete(key, moves);
    final received = c.data.world.rewards.containsKey('game:$key');
    final name = switch (kind) {
      'constellation' => constellations[level].name,
      'parcel' => parcels[level].name,
      _ => expeditions[level].name,
    };
    return ListTile(
      key: ValueKey('world-game-$key'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(switch (kind) {
        'constellation' => Icons.auto_awesome_outlined,
        'parcel' => Icons.inventory_2_outlined,
        _ => Icons.explore_outlined,
      }),
      title: Text(name),
      subtitle: Text(
        received
            ? 'Награда получена · можно повторить'
            : done
            ? 'Завершено'
            : moves.isEmpty
            ? 'Начать'
            : 'Продолжить',
      ),
      trailing: Icon(
        received ? Icons.check_circle_outline : Icons.chevron_right,
      ),
      onTap: () => worldOpen(context, _GameScreen(gameKey: key)),
    );
  }
}

class _GameScreen extends StatefulWidget {
  const _GameScreen({required this.gameKey});
  final String gameKey;
  @override
  State<_GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<_GameScreen> {
  bool _saving = false;
  int _piece = 0;
  String get _kind => widget.gameKey.split(':').first;
  int get _level => WorldGames.levelOf(widget.gameKey);

  Future<void> _save(List<int> moves) async {
    if (_saving) return;
    if (!WorldGames.validate(widget.gameKey, moves)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Предмет не помещается: выберите свободное место подходящей формы.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await FinanceScope.of(context).saveWorldGame(widget.gameKey, moves);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final moves = c.data.world.games[widget.gameKey] ?? const <int>[];
    final done = WorldGames.complete(widget.gameKey, moves);
    final reward = WorldCatalog.rewardFor('game:${widget.gameKey}');
    final received = c.data.world.rewards.containsKey('game:${widget.gameKey}');
    final name = switch (_kind) {
      'constellation' => constellations[_level].name,
      'parcel' => parcels[_level].name,
      _ => expeditions[_level].name,
    };
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        key: const ValueKey('world-game-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_kind == 'constellation') ..._constellation(moves, done),
          if (_kind == 'parcel') ..._parcel(moves, done),
          if (_kind == 'expedition') ..._expedition(moves, done),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          if (done) ...[
            const SizedBox(height: 16),
            SurfaceCard(
              key: const ValueKey('world-game-result'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    _kind == 'expedition' ? 'Путешествие завершено' : 'Готово!',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    received
                        ? 'Награда уже сохранена: ${reward?.xp ?? 0} опыта и ${reward?.sparks ?? 0} искр. Повторная игра не начисляет её снова.'
                        : 'Результат сохранён.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    key: const ValueKey('world-game-replay'),
                    onPressed: _saving ? null : () => _save([]),
                    icon: const Icon(Icons.replay),
                    label: const Text('Играть ещё раз'),
                  ),
                ],
              ),
            ),
          ] else if (moves.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('world-game-undo'),
                  onPressed: _saving
                      ? null
                      : () => _save(moves.take(moves.length - 1).toList()),
                  icon: const Icon(Icons.undo),
                  label: const Text('Назад на шаг'),
                ),
                TextButton(
                  key: const ValueKey('world-game-reset'),
                  onPressed: _saving ? null : () => _save([]),
                  child: const Text('Начать заново'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _constellation(List<int> moves, bool done) {
    final puzzle = constellations[_level];
    return [
      const Text(
        'Соедините звёзды по образцу. Нажимайте на буквы в нужном порядке.',
      ),
      const SizedBox(height: 12),
      SurfaceCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text('Образец'),
            _StarBoard(puzzle: puzzle, moves: puzzle.pattern, reference: true),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < puzzle.pattern.length; i++)
                  Text(
                    '${i + 1}. ${String.fromCharCode(65 + puzzle.pattern[i])}',
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Text('${moves.length} / ${puzzle.pattern.length} звёзд'),
      const SizedBox(height: 8),
      SurfaceCard(
        padding: const EdgeInsets.all(8),
        child: _StarBoard(
          puzzle: puzzle,
          moves: moves,
          reference: false,
          onStar: done || _saving
              ? null
              : (star) {
                  if (star != puzzle.pattern[moves.length]) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Посмотрите на образец: следующая звезда обозначена другой буквой.',
                        ),
                      ),
                    );
                    return;
                  }
                  _save([...moves, star]);
                },
        ),
      ),
    ];
  }

  List<Widget> _parcel(List<int> moves, bool done) {
    final puzzle = parcels[_level];
    final placed = {for (final m in moves) m ~/ 100};
    final occupied = <int, int>{
      for (final m in moves)
        for (final cell in puzzle.cellsAt(m ~/ 100, m % 100)!) cell: m ~/ 100,
    };
    final available = [
      for (var i = 0; i < puzzle.pieces.length; i++)
        if (!placed.contains(i)) i,
    ];
    final selected = available.contains(_piece)
        ? _piece
        : available.firstOrNull;
    return [
      const Text(
        'Уложите все предметы в коробку 3 × 3. Выберите предмет, затем его левую верхнюю ячейку. Предметы не должны пересекаться.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < puzzle.pieces.length; i++)
            ChoiceChip(
              key: ValueKey('world-parcel-piece-$i'),
              label: Text(
                '${i + 1}. ${puzzle.pieces[i].name}${placed.contains(i) ? ' ✓' : ''}',
              ),
              selected: i == selected,
              onSelected: _saving || placed.contains(i) || done
                  ? null
                  : (_) => setState(() => _piece = i),
            ),
        ],
      ),
      if (selected != null) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            _PieceShape(
              piece: puzzle.pieces[selected],
              color: _pieceColor(context, selected),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Форма: ${puzzle.pieces[selected].name}')),
          ],
        ),
      ],
      const SizedBox(height: 16),
      SurfaceCard(
        padding: const EdgeInsets.all(10),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, box) {
              final gap = 6.0, cellSize = (box.maxWidth - gap * 2) / 3;
              return Stack(
                children: [
                  for (var cell = 0; cell < 9; cell++)
                    Positioned(
                      left: cell % 3 * (cellSize + gap),
                      top: cell ~/ 3 * (cellSize + gap),
                      width: cellSize,
                      height: cellSize,
                      child: FilledButton.tonal(
                        key: ValueKey('world-parcel-cell-$cell'),
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          backgroundColor: occupied.containsKey(cell)
                              ? _pieceColor(
                                  context,
                                  occupied[cell]!,
                                ).withValues(alpha: .3)
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          disabledBackgroundColor: occupied.containsKey(cell)
                              ? _pieceColor(
                                  context,
                                  occupied[cell]!,
                                ).withValues(alpha: .3)
                              : null,
                          disabledForegroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface,
                        ),
                        onPressed:
                            _saving ||
                                done ||
                                selected == null ||
                                occupied.containsKey(cell)
                            ? null
                            : () => _save([...moves, selected * 100 + cell]),
                        child: Text(
                          occupied.containsKey(cell)
                              ? '${occupied[cell]! + 1}'
                              : '${cell + 1}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('${moves.length} / ${puzzle.pieces.length} предметов'),
    ];
  }

  List<Widget> _expedition(List<int> moves, bool done) {
    final route = expeditions[_level];
    return [
      for (var i = 0; i < moves.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}. ${route.steps[i].choices[moves[i]]}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(route.steps[i].results[moves[i]]),
              ],
            ),
          ),
        ),
      if (done)
        SurfaceCard(child: Text(route.keepsake))
      else ...[
        Text(
          'Шаг ${moves.length + 1} из ${route.steps.length}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 12),
        Text(
          route.steps[moves.length].text,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        for (var choice = 0; choice < 3; choice++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FilledButton.tonal(
              key: ValueKey('world-expedition-choice-$choice'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              onPressed: _saving ? null : () => _save([...moves, choice]),
              child: Text(
                route.steps[moves.length].choices[choice],
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    ];
  }
}

Color _pieceColor(BuildContext context, int piece) => switch (piece) {
  0 => Theme.of(context).colorScheme.primary,
  1 => const Color(0xffa1d9c4),
  _ => const Color(0xffc6b8e4),
};

class _PieceShape extends StatelessWidget {
  const _PieceShape({required this.piece, required this.color});
  final ParcelPiece piece;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 66,
    height: 66,
    child: Stack(
      children: [
        for (final cell in piece.cells)
          Positioned(
            left: cell.$1 * 22,
            top: cell.$2 * 22,
            width: 20,
            height: 20,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: .7),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
      ],
    ),
  );
}

class _StarBoard extends StatelessWidget {
  const _StarBoard({
    required this.puzzle,
    required this.moves,
    required this.reference,
    this.onStar,
  });
  final ConstellationPuzzle puzzle;
  final List<int> moves;
  final bool reference;
  final ValueChanged<int>? onStar;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: reference ? 140 : 260,
    child: LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final color = Theme.of(context).colorScheme.primary;
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ConstellationPainter(puzzle, moves, color),
              ),
            ),
            for (var i = 0; i < puzzle.points.length; i++)
              Positioned(
                left: (puzzle.points[i].x * (size.width - 48)),
                top: (puzzle.points[i].y * (size.height - 48)),
                width: 48,
                height: 48,
                child: reference
                    ? Center(
                        child: Text(
                          String.fromCharCode(65 + i),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      )
                    : IconButton.filledTonal(
                        key: ValueKey('world-star-$i'),
                        tooltip: 'Звезда ${String.fromCharCode(65 + i)}',
                        onPressed: onStar == null || moves.contains(i)
                            ? null
                            : () => onStar!(i),
                        style: IconButton.styleFrom(
                          backgroundColor: moves.contains(i)
                              ? color.withValues(alpha: .24)
                              : null,
                          disabledBackgroundColor: moves.contains(i)
                              ? color.withValues(alpha: .24)
                              : null,
                          disabledForegroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface,
                        ),
                        icon: Text(
                          String.fromCharCode(65 + i),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
              ),
          ],
        );
      },
    ),
  );
}

class _ConstellationPainter extends CustomPainter {
  const _ConstellationPainter(this.puzzle, this.moves, this.color);
  final ConstellationPuzzle puzzle;
  final List<int> moves;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    Offset at(int i) => Offset(
      puzzle.points[i].x * (size.width - 48) + 24,
      puzzle.points[i].y * (size.height - 48) + 24,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: .45)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < moves.length; i++) {
      canvas.drawLine(at(moves[i - 1]), at(moves[i]), paint);
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter oldDelegate) =>
      oldDelegate.moves != moves ||
      oldDelegate.color != color ||
      oldDelegate.puzzle != puzzle;
}
