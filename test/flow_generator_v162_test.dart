import 'dart:io';

import 'package:finora/domain/flow/flow.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/flow_bot.dart';

/// 1.62: 500 levels — twenty hand-made, then generated ones with walls,
/// chains and crates arriving one at a time.
bool _fair(FlowLevel l, ({bool won, int used, FlowSession end}) r) =>
    r.won && l.moves - r.used >= (l.moves * .15).ceil().clamp(2, 99);

void main() {
  final made = FlowLevels.decode(
    File('assets/flow/levels.json').readAsStringSync(),
  );
  final generated = FlowLevelGenerator.all();

  test('ids run 1–500 without gaps; generation is repeatable and valid', () {
    final ids = [...made, ...generated].map((l) => l.id).toList();
    expect(ids, [for (var i = 1; i <= flowLevelCount; i++) i]);
    expect(flowLevelCount, 500);
    for (final level in generated) {
      FlowLevels.validate(level); // a stable, playable first board
      expect(
        FlowLevelGenerator.generate(level.id).toJson(),
        level.toJson(),
        reason: 'level ${level.id}',
      );
      expect(level.chapterId, (level.id - 1) ~/ 50 + 1);
      expect(level.moves, inInclusiveRange(12, 60));
      // Obstacles stay off the edges and the bottom row.
      for (final o in level.obstacles.where((o) => o.kind != 'wall')) {
        expect(o.index ~/ 8, inInclusiveRange(1, 6));
        expect(o.index % 8, inInclusiveRange(1, 6));
      }
    }
  });

  test('new obstacles arrive one at a time, with a word of help', () {
    FlowLevel at(int id) => generated.firstWhere((l) => l.id == id);
    bool uses(int id, String kind) =>
        at(id).obstacles.any((o) => o.kind == kind);
    for (final l in generated.where(
      (l) => l.id < FlowLevelGenerator.wallsFrom,
    )) {
      expect(l.obstacles.any((o) => o.kind == 'wall'), isFalse);
    }
    expect(uses(FlowLevelGenerator.wallsFrom, 'wall'), isTrue);
    expect(at(FlowLevelGenerator.wallsFrom).tutorial, contains('Стенки'));
    for (final l in generated.where(
      (l) => l.id < FlowLevelGenerator.chainsFrom,
    )) {
      expect(l.obstacles.any((o) => o.kind == 'chain'), isFalse);
    }
    // The newcomer is the level's only obstacle (walls aside), and a goal.
    expect(
      at(
        FlowLevelGenerator.chainsFrom,
      ).obstacles.where((o) => o.kind != 'wall').map((o) => o.kind).toSet(),
      {'chain'},
    );
    expect(
      at(FlowLevelGenerator.chainsFrom).goals.map((g) => g.key),
      contains('chain'),
    );
    expect(at(FlowLevelGenerator.chainsFrom).tutorial, isNotEmpty);
    for (final l in generated.where(
      (l) => l.id < FlowLevelGenerator.cratesFrom,
    )) {
      expect(l.obstacles.any((o) => o.kind == 'crate'), isFalse);
    }
    // The newcomer is the level's only obstacle (walls aside), and a goal.
    expect(
      at(
        FlowLevelGenerator.cratesFrom,
      ).obstacles.where((o) => o.kind != 'wall').map((o) => o.kind).toSet(),
      {'crate'},
    );
    expect(
      at(FlowLevelGenerator.cratesFrom).goals.map((g) => g.key),
      contains('crate'),
    );
    expect(at(FlowLevelGenerator.cratesFrom).tutorial, isNotEmpty);
    // Later levels mix them, and walls shape many boards.
    final late = generated.where((l) => l.id > 300).toList();
    expect(
      late.where((l) => l.obstacles.any((o) => o.kind == 'wall')).length,
      greaterThan(late.length ~/ 3),
    );
    expect(
      late.where((l) => l.goals.length >= 2).length,
      greaterThan(late.length ~/ 2),
    );
  });

  test('a greedy test player finishes every generated level with a margin', () {
    final calibrate = Platform.environment['FLOW_CALIBRATE'] == '1';
    final table = <int, int>{};
    final unfair = <int>[];
    for (var id = FlowLevelGenerator.first; id <= flowLevelCount; id++) {
      if (calibrate) {
        for (var v = 0; v < 40; v++) {
          final l = FlowLevelGenerator.build(id, v);
          try {
            FlowLevels.validate(l);
          } on Object {
            continue;
          }
          if (_fair(l, playGreedy(l))) {
            if (v > 0) table[id] = v;
            break;
          }
        }
        continue;
      }
      final l = FlowLevelGenerator.generate(id);
      if (!_fair(l, playGreedy(l))) unfair.add(id);
    }
    if (calibrate) {
      // ignore: avoid_print
      print(table.entries.map((e) => '${e.key}: ${e.value},').join(' '));
      return;
    }
    expect(unfair, isEmpty, reason: 'recalibrate FlowLevelGenerator.variants');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('walls: nothing moves through or breaks them', () {
    final level = generated.firstWhere(
      (l) => l.id == FlowLevelGenerator.wallsFrom,
    );
    final walls = {
      for (final o in level.obstacles)
        if (o.kind == 'wall') o.index,
    };
    final session = FlowEngine.newGame(level);
    for (final w in walls) {
      expect(session.board[w].wall, isTrue);
      expect(session.board[w].movable, isFalse);
      expect(session.board[w].empty, isFalse);
    }
    // A hammer on a wall is refused (and so not spent).
    final hammer = FlowEngine.useTool(
      level,
      session,
      FlowTool.hammer,
      cell: walls.first,
    );
    expect(hammer.accepted, isFalse);
    // A bomb next to it, swaps and cascades leave every wall in place.
    final bomb = FlowEngine.useTool(
      level,
      session,
      FlowTool.bomb,
      cell: walls.first,
    );
    expect(bomb.accepted, isTrue);
    var s = bomb.session;
    for (var turn = 0; turn < 8 && s.status == FlowStatus.active; turn++) {
      final moves = FlowEngine.legalMoves(s);
      for (final m in moves) {
        expect(walls.contains(m.$1) || walls.contains(m.$2), isFalse);
      }
      s = FlowEngine.swap(level, s, moves.first.$1, moves.first.$2).session;
      for (var i = 0; i < 64; i++) {
        expect(s.board[i].wall, walls.contains(i), reason: 'cell $i');
      }
      FlowEngine.validateSession(level, s);
    }
    // Walls survive a save.
    final copy = FlowSession.fromJson(s.toJson());
    expect(
      [for (final c in copy.board) c.wall],
      [for (final c in s.board) c.wall],
    );
  });

  test('progress unlocks past 20, up to 500', () {
    final results = {
      for (var i = 1; i <= 120; i++)
        i: const FlowResult(stars: 1, bestScore: 10),
    };
    final flow = FlowProgress(results: results);
    expect(flow.highestUnlocked, 121);
    expect(flow.isUnlocked(121), isTrue);
    expect(flow.isUnlocked(122), isFalse);
    final all = FlowProgress(
      results: {
        for (var i = 1; i <= 500; i++)
          i: const FlowResult(stars: 3, bestScore: 10),
      },
    );
    expect(all.highestUnlocked, 500);
    expect(all.isUnlocked(500), isTrue);
    expect(all.isUnlocked(501), isFalse);
  });
}
