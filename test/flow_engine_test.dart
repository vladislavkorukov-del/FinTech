import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/flow/flow.dart';
import 'package:flutter_test/flutter_test.dart';

FlowLevel level({
  int moves = 20,
  List<FlowGoal> goals = const [FlowGoal('collect:coin', 9999)],
  List<FlowObstacle> obstacles = const [],
  int seed = 123,
}) => FlowLevel(
  id: 1,
  name: 'Test',
  seed: seed,
  moves: moves,
  goals: goals,
  obstacles: obstacles,
  scoreThresholds: const [0, 200, 600],
);
List<FlowCell> latin() => List.generate(
  64,
  (i) => FlowCell(tile: FlowTile.values[((i ~/ 8) * 2 + i % 8) % 6]),
);
FlowSession session(List<FlowCell> board, {int moves = 20, int seed = 123}) =>
    FlowSession(
      levelId: 1,
      board: board,
      remainingMoves: moves,
      score: 0,
      progress: {},
      rngState: seed,
    );
List<FlowEvent> firstChain(FlowTurn turn) =>
    turn.events.where((e) => e.chain == 0).toList();
void paint(List<FlowCell> board, List<int> cells, FlowTile tile) {
  for (final i in cells) {
    board[i] = FlowCell(tile: tile);
  }
}

void main() {
  test('seeded initial generation is stable, playable, and reproducible', () {
    for (var seed = 1; seed <= 80; seed++) {
      final l = level(seed: seed),
          a = FlowEngine.newGame(level(seed: seed)),
          b = FlowEngine.newGame(level(seed: seed));
      expect(a.toJson(), b.toJson());
      expect(a.board.length, 64);
      expect(a.board.every((c) => !c.empty), isTrue);
      expect(FlowEngine.detect(a.board), isEmpty);
      expect(FlowEngine.legalMoves(a), isNotEmpty);
      FlowEngine.validateSession(l, a);
    }
  });
  test(
    'nonadjacent, row wrapping and empty swaps do not consume moves or state',
    () {
      final l = level(), s = FlowEngine.newGame(l);
      for (final pair in [(0, 2), (7, 8), (-1, 0), (63, 64)]) {
        final result = FlowEngine.swap(l, s, pair.$1, pair.$2);
        expect(result.accepted, isFalse);
        expect(identical(result.session, s), isTrue);
      }
      final legal = FlowEngine.legalMoves(s).toSet();
      final invalid = [
        for (var i = 0; i < 63; i++)
          if (i % 8 < 7 && !legal.contains((i, i + 1))) (i, i + 1),
      ].first;
      expect(
        FlowEngine.swap(l, s, invalid.$1, invalid.$2).session.toJson(),
        s.toJson(),
      );
    },
  );
  test(
    'detector classifies3,4,5+,square,T/L and stable placement priority',
    () {
      final cases = <({List<int> cells, FlowBooster kind})>[
        (cells: [24, 25, 26], kind: FlowBooster.none),
        (cells: [24, 25, 26, 27], kind: FlowBooster.rocketRow),
        (cells: [3, 11, 19, 27], kind: FlowBooster.rocketColumn),
        (cells: [24, 25, 26, 27, 28], kind: FlowBooster.core),
        (cells: [19, 26, 27, 28, 35], kind: FlowBooster.bomb),
        (cells: [19, 27, 35, 36, 37], kind: FlowBooster.bomb),
        (cells: [27, 28, 35, 36], kind: FlowBooster.drone),
      ];
      for (final c in cases) {
        final b = latin();
        paint(b, c.cells, FlowTile.coin);
        final found = FlowEngine.detect(
          b,
          from: c.cells.first,
          to: c.cells.last,
        ).where((m) => m.cells.containsAll(c.cells)).single;
        expect(found.booster, c.kind, reason: '${c.cells}');
        if (c.kind != FlowBooster.none) expect(found.position, c.cells.last);
      }
      final diagonal = latin();
      paint(diagonal, [9, 18, 27], FlowTile.coin);
      expect(
        FlowEngine.detect(
          diagonal,
        ).any((m) => m.cells.containsAll([9, 18, 27])),
        isFalse,
      );
    },
  );
  test(
    'overlapping core outranksTL and each connected figure produces one booster',
    () {
      final b = latin();
      paint(b, [24, 25, 26, 27, 28, 19, 35], FlowTile.coin);
      final m = FlowEngine.detect(
        b,
        from: 19,
        to: 27,
      ).where((m) => m.cells.contains(27)).single;
      expect(m.booster, FlowBooster.core);
      expect(m.position, 27);
      final other = latin();
      paint(other, [0, 1, 2, 3], FlowTile.coin);
      paint(other, [56, 57, 58, 59], FlowTile.wallet);
      expect(
        FlowEngine.detect(
          other,
        ).where((m) => m.booster != FlowBooster.none).length,
        2,
      );
    },
  );
  test(
    'ordinary matched move consumes exactly one move across all cascades and restores RNG exactly',
    () {
      final l = level(), s = FlowEngine.newGame(level());
      final m = FlowEngine.legalMoves(s).first;
      final a = FlowEngine.swap(l, s, m.$1, m.$2);
      expect(a.accepted, isTrue);
      expect(a.session.remainingMoves, 19);
      expect(a.events.where((e) => e.kind == 'collect'), isNotEmpty);
      expect(FlowEngine.detect(a.session.board), isEmpty);
      final loaded = FlowSession.fromJson(
        jsonDecode(jsonEncode(a.session.toJson())) as Map<String, dynamic>,
      );
      final next = FlowEngine.legalMoves(a.session).first;
      expect(
        FlowEngine.swap(l, a.session, next.$1, next.$2).session.toJson(),
        FlowEngine.swap(l, loaded, next.$1, next.$2).session.toJson(),
      );
    },
  );
  test(
    'frozen tile cannot move and a direct hit removes only a layer, not the tile',
    () {
      final b = latin();
      b[27] = const FlowCell(
        tile: FlowTile.shield,
        booster: FlowBooster.rocketColumn,
      );
      b[11] = const FlowCell(tile: FlowTile.coin, ice: 2);
      final l = level(
            goals: const [FlowGoal('ice', 1), FlowGoal('collect:coin', 9999)],
          ),
          s = session(b);
      expect(FlowEngine.swap(l, s, 11, 12).accepted, isFalse);
      // Rocket moves27->28 and clears column4; freeze there to inspect an actual hit.
      b[12] = const FlowCell(tile: FlowTile.coin, ice: 2);
      final turn = FlowEngine.swap(l, session(b), 27, 28);
      final hit = firstChain(turn);
      expect(
        hit.where((e) => e.kind == 'iceDamage' && e.index == 12).length,
        1,
      );
      expect(hit.where((e) => e.kind == 'collect' && e.index == 12), isEmpty);
      expect(turn.session.board[12].tile, FlowTile.coin);
      expect(turn.session.board[12].ice, 1);
    },
  );
  test(
    'receipt stack direct/adjacent overlapping hits damage it once per event',
    () {
      final b = latin();
      b[27] = const FlowCell(tile: FlowTile.shield, booster: FlowBooster.bomb);
      b[28] = const FlowCell(tile: FlowTile.receipt, booster: FlowBooster.bomb);
      b[20] = const FlowCell(stack: 3);
      final turn = FlowEngine.swap(level(), session(b), 27, 28);
      expect(
        firstChain(
          turn,
        ).where((e) => e.kind == 'stackDamage' && e.index == 20).length,
        1,
      );
      expect(turn.session.board[20].stack, 2);
    },
  );
  test(
    'each rocket orientation,bomb,drone and core activates once within a chain',
    () {
      for (final booster in FlowBooster.values.where(
        (e) => e != FlowBooster.none,
      )) {
        final b = latin();
        b[27] = FlowCell(
          tile: booster == FlowBooster.core ? null : FlowTile.shield,
          booster: booster,
        );
        final turn = FlowEngine.swap(level(), session(b), 27, 28);
        expect(turn.accepted, isTrue);
        expect(
          firstChain(turn)
              .where(
                (e) =>
                    e.kind == 'activate' &&
                    e.index == 28 &&
                    e.booster == booster,
              )
              .length,
          1,
          reason: booster.name,
        );
      }
    },
  );
  test(
    'rocket+rocket union row/column; rocket+bomb3rows/3columns; bomb+bomb5x5',
    () {
      for (final pair in [
        (FlowBooster.rocketRow, FlowBooster.rocketColumn),
        (FlowBooster.rocketRow, FlowBooster.bomb),
        (FlowBooster.bomb, FlowBooster.bomb),
      ]) {
        final b = latin();
        b[27] = FlowCell(tile: FlowTile.shield, booster: pair.$1);
        b[28] = FlowCell(tile: FlowTile.receipt, booster: pair.$2);
        final turn = FlowEngine.swap(level(), session(b), 27, 28);
        final cleared = firstChain(
          turn,
        ).where((e) => e.kind == 'collect').map((e) => e.index).toSet();
        final expected = <int>{
          27,
          28,
          for (var i = 0; i < 64; i++)
            if (pair.$1 == FlowBooster.bomb
                ? (i ~/ 8 - 3).abs() <= 2 && (i % 8 - 4).abs() <= 2
                : pair.$2 == FlowBooster.bomb
                ? (i ~/ 8 - 3).abs() <= 1 || (i % 8 - 4).abs() <= 1
                : i ~/ 8 == 3 || i % 8 == 4)
              i,
        };
        expect(cleared, expected, reason: '$pair');
        final raw = firstChain(
          turn,
        ).where((e) => e.kind == 'collect').map((e) => e.index).toList();
        expect(raw.toSet().length, raw.length);
      }
    },
  );
  test(
    'core+normal clears chosen type and never counts a core as a colored tile',
    () {
      final b = latin();
      b[27] = const FlowCell(booster: FlowBooster.core);
      final target = b[28].tile;
      final expected = {
        27,
        for (var i = 0; i < 64; i++)
          if (b[i].tile == target) i,
      }..remove(27);
      // After swapping, partner occupies27; original28 becomes the colorless core.
      expected.remove(28);
      expected.add(27);
      final turn = FlowEngine.swap(level(), session(b), 27, 28);
      final cleared = firstChain(
        turn,
      ).where((e) => e.kind == 'collect').toList();
      expect(cleared.map((e) => e.index).toSet(), expected);
      expect(cleared.every((e) => e.tile == target), isTrue);
    },
  );
  test(
    'core+rocket/core+bomb transforms all partner-type cells and activates once',
    () {
      for (final kind in [FlowBooster.rocketRow, FlowBooster.bomb]) {
        final b = latin();
        b[27] = const FlowCell(booster: FlowBooster.core);
        b[28] = FlowCell(tile: FlowTile.receipt, booster: kind);
        final originalCount = b.where((e) => e.tile == FlowTile.receipt).length;
        final turn = FlowEngine.swap(level(), session(b), 27, 28);
        final activations = firstChain(
          turn,
        ).where((e) => e.kind == 'activate' && e.booster == kind).toList();
        expect(activations.length, originalCount);
        expect(activations.map((e) => e.index).toSet().length, originalCount);
      }
    },
  );
  test(
    'core+core clears all64 cells once; last-move victory takes priority over loss',
    () {
      final b = latin();
      b[27] = const FlowCell(booster: FlowBooster.core);
      b[28] = const FlowCell(booster: FlowBooster.core);
      final l = level(moves: 1, goals: const [FlowGoal('collect:coin', 1)]),
          turn = FlowEngine.swap(l, session(b, moves: 1), 27, 28);
      expect(firstChain(turn).where((e) => e.kind == 'collect').length, 62);
      expect(turn.session.remainingMoves, 0);
      expect(turn.session.status, FlowStatus.won);
      expect(turn.session.stars(l), greaterThanOrEqualTo(1));
      final loss = FlowEngine.swap(
        level(moves: 1),
        session(b, moves: 1),
        27,
        28,
      );
      expect(loss.session.status, FlowStatus.lost);
    },
  );
  test(
    'drone prioritizes required obstacle, then needed tile, one target per activation',
    () {
      final b = latin();
      b[27] = const FlowCell(tile: FlowTile.shield, booster: FlowBooster.drone);
      b[5] = const FlowCell(stack: 2);
      b[3] = const FlowCell(tile: FlowTile.wallet, ice: 2);
      final turn = FlowEngine.swap(
        level(goals: const [FlowGoal('stack', 1)]),
        session(b),
        27,
        28,
      );
      expect(
        firstChain(
          turn,
        ).where((e) => e.kind == 'stackDamage').map((e) => e.index),
        [5],
      );
      expect(firstChain(turn).where((e) => e.kind == 'iceDamage'), isEmpty);
      final next = latin();
      next[27] = const FlowCell(
        tile: FlowTile.shield,
        booster: FlowBooster.drone,
      );
      final t = FlowEngine.swap(
        level(goals: const [FlowGoal('collect:coin', 2)]),
        session(next),
        27,
        28,
      );
      expect(firstChain(t).where((e) => e.kind == 'collect').length, 2);
      expect(
        firstChain(
          t,
        ).where((e) => e.kind == 'collect' && e.index != 28).single.tile,
        FlowTile.coin,
      );
    },
  );
  test('chain hits cannot activate an already removed booster twice', () {
    final b = latin();
    b[27] = const FlowCell(tile: FlowTile.shield, booster: FlowBooster.bomb);
    b[28] = const FlowCell(tile: FlowTile.receipt, booster: FlowBooster.drone);
    b[20] = const FlowCell(tile: FlowTile.goal, booster: FlowBooster.bomb);
    final t = FlowEngine.swap(level(), session(b), 27, 28);
    final first = firstChain(
      t,
    ).where((e) => e.kind == 'activate').map((e) => e.index).toList();
    expect(first.toSet().length, first.length);
  });
  test(
    'no-move board shuffles boundedly without score,goal or move progress',
    () {
      final s = session(latin());
      expect(FlowEngine.legalMoves(s), isEmpty);
      final turn = FlowEngine.ensurePlayable(level(), s);
      expect(turn.shuffled, isTrue);
      expect(turn.session.score, 0);
      expect(turn.session.remainingMoves, 20);
      expect(turn.session.progress, isEmpty);
      expect(FlowEngine.detect(turn.session.board), isEmpty);
      expect(FlowEngine.legalMoves(turn.session), isNotEmpty);
      final before = s.board.map((c) => c.tile!.index).toList()..sort(),
          after = turn.session.board.map((c) => c.tile!.index).toList()..sort();
      expect(after, before);
    },
  );
  test(
    'result stars and best score only improve; corrupt session leaves other results intact',
    () {
      final l = level(),
          won = FlowSession(
            levelId: 1,
            board: latin(),
            remainingMoves: 5,
            score: 800,
            progress: {'collect:coin': 9999},
            rngState: 123,
            status: FlowStatus.won,
          );
      var p = const FlowProgress().record(won, l);
      expect(p.results[1]!.stars, 3);
      expect(p.highestUnlocked, 2);
      expect(p.isUnlocked(3), isFalse);
      final weaker = FlowSession(
        levelId: 1,
        board: latin(),
        remainingMoves: 0,
        score: 50,
        progress: {'collect:coin': 9999},
        rngState: 123,
        status: FlowStatus.won,
      );
      p = p.record(weaker, l);
      expect(p.results[1]!.stars, 3);
      expect(p.results[1]!.bestScore, 800);
      final j = p.toJson();
      (j['session'] as Map)['board'] = [];
      final loaded = FlowProgress.fromJson(j);
      expect(loaded.results[1]!.bestScore, 800);
      expect(loaded.session, isNull);
      final merged = FlowProgress.merge(
        p,
        const FlowProgress(results: {1: FlowResult(stars: 2, bestScore: 900)}),
      );
      expect(merged.results[1]!.stars, 3);
      expect(merged.results[1]!.bestScore, 900);
    },
  );
  test(
    'loader rejects unsupported masks, invalid goals/obstacles/types/thresholds/layouts',
    () {
      final j = level().toJson();
      for (final change in <Map<String, Object?>>[
        {'boardMask': []},
        {'width': 7},
        {'moves': 0},
        {
          'availableTileTypes': ['coin', 'wallet', 'unknown'],
        },
        {
          'goals': [
            {'key': 'collect:unknown', 'target': 1},
          ],
        },
        {
          'obstacles': [
            {'index': 70, 'kind': 'stack', 'layers': 1},
          ],
        },
        {
          'scoreThresholds': [10, 10, 100],
        },
      ]) {
        expect(
          () => FlowLevels.decode(
            jsonEncode({
              'schemaVersion': 1,
              'levels': [
                {...j, ...change},
              ],
            }),
          ),
          throwsA(anything),
        );
      }
      expect(
        () => FlowLevels.validate(level(goals: const [FlowGoal('ice', 1)])),
        throwsFormatException,
      );
      final matched = latin();
      paint(matched, [0, 1, 2], FlowTile.coin);
      final saved = session(matched).toJson();
      expect(() => FlowSession.fromJson(saved), throwsFormatException);
      expect(
        () => FlowCell.fromJson({
          'tile': null,
          'booster': 'bomb',
          'ice': 0,
          'stack': 0,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'all20 level definitions and stored winning replays execute successfully',
    () {
      final levelsFile = File('assets/flow/levels.json'),
          replaysFile = File('assets/flow/winning_replays.json');
      expect(levelsFile.existsSync(), isTrue);
      expect(replaysFile.existsSync(), isTrue);
      final levels = FlowLevels.decode(levelsFile.readAsStringSync());
      expect(levels.length, 20);
      expect(levels.map((e) => e.id), List.generate(20, (i) => i + 1));
      final replays =
          (jsonDecode(replaysFile.readAsStringSync()) as Map)['levels'] as List;
      expect(replays.length, 20);
      for (final l in levels) {
        final r = replays.cast<Map>().singleWhere((r) => r['levelId'] == l.id);
        expect(r['seed'], l.seed);
        var s = FlowEngine.newGame(l);
        for (final m in r['moves'] as List) {
          final t = FlowEngine.swap(l, s, m[0] as int, m[1] as int);
          expect(t.accepted, isTrue, reason: 'level${l.id}');
          s = t.session;
          FlowEngine.validateSession(l, s);
        }
        expect(s.status, FlowStatus.won, reason: 'level${l.id}');
        expect(s.score, r['score']);
        expect(s.stars(l), r['stars']);
      }
    },
  );
}
