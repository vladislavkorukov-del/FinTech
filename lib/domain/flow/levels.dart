import 'dart:convert';
import 'models.dart';
import 'engine.dart';

abstract final class FlowLevels {
  static List<FlowLevel> decode(String source) {
    final j = jsonDecode(source);
    if (j is! Map ||
        j['schemaVersion'] != 1 ||
        j.keys.any((k) => !{'schemaVersion', 'levels'}.contains(k)) ||
        j['levels'] is! List) {
      throw const FormatException('Invalid flow level catalog');
    }
    final levels = (j['levels'] as List)
        .map((e) => FlowLevel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (levels.isEmpty ||
        levels.map((e) => e.id).toSet().length != levels.length) {
      throw const FormatException('Duplicate flow level IDs');
    }
    for (final level in levels) {
      validate(level);
    }
    return List.unmodifiable(levels);
  }

  static void validate(FlowLevel level) {
    if (level.id < 1 ||
        level.id > 500 ||
        level.seed < 1 ||
        level.seed > 0xffffffff ||
        level.chapterId < 1 ||
        level.chapterId > 10 ||
        level.moves > 100 ||
        level.scoreThresholds.length != 3 ||
        level.scoreThresholds[0] < 0 ||
        level.scoreThresholds[0] >= level.scoreThresholds[1] ||
        level.scoreThresholds[1] >= level.scoreThresholds[2] ||
        level.name.trim().isEmpty ||
        level.types.length < 3 ||
        level.types.toSet().length != level.types.length ||
        level.moves < 1 ||
        level.goals.isEmpty ||
        level.goals.map((g) => g.key).toSet().length != level.goals.length ||
        level.obstacles.map((e) => e.index).toSet().length !=
            level.obstacles.length) {
      throw const FormatException('Invalid level definition');
    }
    for (final o in level.obstacles) {
      if (o.index < 0 ||
          o.index >= 64 ||
          o.layers < 1 ||
          o.layers > 5 ||
          !{'ice', 'stack'}.contains(o.kind)) {
        throw const FormatException('Invalid obstacle');
      }
    }
    for (final g in level.goals) {
      if (g.target <= 0 ||
          g.target > 10000 ||
          !{
            'ice',
            'stack',
            ...FlowTile.values.map((t) => 'collect:${t.name}'),
          }.contains(g.key)) {
        throw const FormatException('Invalid target');
      }
      if (g.key.startsWith('collect:') &&
          !level.types.any((t) => g.key == 'collect:${t.name}')) {
        throw const FormatException('Unavailable target tile');
      }
      if ({'ice', 'stack'}.contains(g.key) &&
          level.obstacles.where((o) => o.kind == g.key).length < g.target) {
        throw const FormatException('Unavailable obstacle target');
      }
    }
    final session = FlowEngine.newGame(level);
    final declared = {
      for (final obstacle in level.obstacles) obstacle.index: obstacle,
    };
    for (var i = 0; i < 64; i++) {
      final c = session.board[i];
      FlowCell.fromJson(c.toJson());
      final obstacle = declared[i];
      if (c.stack > 0 &&
              (obstacle?.kind != 'stack' || obstacle?.layers != c.stack) ||
          c.ice > 0 && (obstacle?.kind != 'ice' || obstacle?.layers != c.ice) ||
          obstacle?.kind == 'ice' && c.ice != obstacle?.layers ||
          obstacle?.kind == 'stack' && c.stack != obstacle?.layers) {
        throw const FormatException(
          'Obstacle declaration does not match initial layout',
        );
      }
      if (c.tile != null && !level.types.contains(c.tile)) {
        throw const FormatException('Unsupported board tile');
      }
      if (c.ice > 0) {
        final adj = <int>[
          if (i % 8 > 0) i - 1,
          if (i % 8 < 7) i + 1,
          if (i >= 8) i - 8,
          if (i < 56) i + 8,
        ];
        if (adj.every((n) => session.board[n].stack > 0)) {
          throw const FormatException('Unreachable frozen tile');
        }
      }
    }
    final move = level.teachingMove;
    if (move != null &&
        !FlowEngine.legalMoves(
          session,
        ).any((m) => m == move || (m.$1 == move.$2 && m.$2 == move.$1))) {
      throw const FormatException('Unavailable teaching move');
    }
  }
}
