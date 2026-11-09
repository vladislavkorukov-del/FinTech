import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/flow/flow.dart';
import 'package:flutter_test/flutter_test.dart';

FlowLevel _level({
  List<FlowGoal> goals = const [FlowGoal('collect:coin', 9999)],
}) => FlowLevel(
  id: 1,
  name: 'Independent contract',
  seed: 137,
  moves: 30,
  goals: goals,
  scoreThresholds: const [0, 500, 1000],
);

FlowSession _snapshot(List<FlowCell> board) => FlowSession(
  levelId: 1,
  board: board,
  remainingMoves: 30,
  score: 0,
  progress: const {},
  rngState: 137,
);

void main() {
  test(
    'drone fallback targets an ordinary accessible tile, not unrelated obstacles',
    () {
      const colors = [
        FlowTile.wallet,
        FlowTile.goal,
        FlowTile.shield,
        FlowTile.receipt,
        FlowTile.chart,
      ];
      final board = List.generate(
        64,
        (i) => FlowCell(tile: colors[(i ~/ 8 * 2 + i % 8) % colors.length]),
      );
      board[0] = const FlowCell(stack: 2);
      board[27] = const FlowCell(
        tile: FlowTile.wallet,
        booster: FlowBooster.drone,
      );
      expect(FlowEngine.detect(board), isEmpty);
      final turn = FlowEngine.swap(_level(), _snapshot(board), 27, 28);
      expect(turn.accepted, isTrue);
      final firstTarget = turn.events.firstWhere(
        (e) => e.chain == 0 && e.kind != 'activate' && e.index != 28,
      );
      expect(
        firstTarget.kind,
        'collect',
        reason:
            'Without a matching goal target, a drone must select an ordinary accessible tile',
      );
      expect(board[firstTarget.index].movable, isTrue);
      expect(board[firstTarget.index].booster, FlowBooster.none);
    },
  );

  test(
    'level validator rejects unknown and duplicate goals at its public seam',
    () {
      expect(
        () => FlowLevels.validate(_level(goals: const [FlowGoal('score', 1)])),
        throwsFormatException,
      );
      expect(
        () => FlowLevels.validate(
          _level(
            goals: const [
              FlowGoal('collect:coin', 1),
              FlowGoal('collect:coin', 2),
            ],
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'deterministic random legal traces preserve stable state and goal/event counts',
    () {
      final levels = FlowLevels.decode(
        File('assets/flow/levels.json').readAsStringSync(),
      );
      for (final level in levels) {
        var left = FlowEngine.newGame(level);
        var right = FlowSession.fromJson(
          jsonDecode(jsonEncode(left.toJson())) as Map<String, dynamic>,
        );
        for (var step = 0; step < level.moves && !left.finished; step++) {
          final moves = FlowEngine.legalMoves(left);
          expect(moves, isNotEmpty, reason: 'level${level.id}/step$step');
          final move = moves[(level.id * 31 + step * 17) % moves.length];
          final a = FlowEngine.swap(level, left, move.$1, move.$2);
          final b = FlowEngine.swap(level, right, move.$1, move.$2);
          expect(a.accepted, isTrue);
          expect(a.session.remainingMoves, left.remainingMoves - 1);
          expect(
            a.session.toJson(),
            b.session.toJson(),
            reason: 'level${level.id}/step$step',
          );
          expect(FlowEngine.detect(a.session.board), isEmpty);
          FlowEngine.validateSession(level, a.session);
          for (final type in FlowTile.values) {
            final before = left.progress['collect:${type.name}'] ?? 0;
            final after = a.session.progress['collect:${type.name}'] ?? 0;
            expect(
              after - before,
              a.events
                  .where(
                    (event) => event.kind == 'collect' && event.tile == type,
                  )
                  .length,
            );
          }
          expect(
            (a.session.progress['ice'] ?? 0) - (left.progress['ice'] ?? 0),
            a.events.where((event) => event.kind == 'ice').length,
          );
          expect(
            (a.session.progress['stack'] ?? 0) - (left.progress['stack'] ?? 0),
            a.events.where((event) => event.kind == 'stack').length,
          );
          left = a.session;
          right = FlowSession.fromJson(
            jsonDecode(jsonEncode(b.session.toJson())) as Map<String, dynamic>,
          );
        }
      }
    },
  );
}
