import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/flow/flow.dart';

const _catalogPath = 'assets/flow/levels.json';
const _replayPath = 'assets/flow/winning_replays.json';

class _Plan {
  const _Plan(
    this.name,
    this.moves,
    this.goals, {
    this.ice = 0,
    this.iceLayers = 1,
    this.stacks = 0,
    this.stackLayers = 1,
    this.lesson,
    this.combo,
  });
  final String name;
  final int moves, ice, iceLayers, stacks, stackLayers;
  final List<FlowGoal> goals;
  final FlowBooster? lesson;
  final (FlowBooster, FlowBooster)? combo;
}

const _plans = [
  _Plan('Первая цепочка', 9, [FlowGoal('collect:coin', 9)]),
  _Plan('Карманный порядок', 11, [FlowGoal('collect:wallet', 12)]),
  _Plan('Верная цель', 13, [FlowGoal('collect:goal', 15)]),
  _Plan('Ракета по горизонтали', 16, [
    FlowGoal('collect:coin', 15),
    FlowGoal('collect:wallet', 12),
  ], lesson: FlowBooster.rocketRow),
  _Plan('Ракета по вертикали', 17, [
    FlowGoal('collect:shield', 16),
    FlowGoal('collect:chart', 12),
  ], lesson: FlowBooster.rocketColumn),
  _Plan('Две линии порядка', 19, [
    FlowGoal('collect:receipt', 18),
    FlowGoal('collect:coin', 18),
  ], lesson: FlowBooster.rocketRow),
  _Plan('Мягкий Fin-взрыв', 20, [
    FlowGoal('collect:goal', 18),
    FlowGoal('collect:shield', 18),
  ], lesson: FlowBooster.bomb),
  _Plan('Ядро Финоры', 21, [
    FlowGoal('collect:wallet', 20),
    FlowGoal('collect:chart', 20),
  ], lesson: FlowBooster.core),
  _Plan('Центр притяжения', 22, [
    FlowGoal('collect:coin', 24),
    FlowGoal('collect:receipt', 24),
  ], lesson: FlowBooster.core),
  _Plan(
    'Первый полёт дрона',
    20,
    [FlowGoal('ice', 2), FlowGoal('collect:shield', 14)],
    ice: 2,
    lesson: FlowBooster.drone,
  ),
  _Plan('Монеты подо льдом', 22, [
    FlowGoal('ice', 3),
    FlowGoal('collect:coin', 18),
  ], ice: 3),
  _Plan(
    'Двойной лёд',
    26,
    [FlowGoal('ice', 4), FlowGoal('collect:goal', 20)],
    ice: 4,
    iceLayers: 2,
    lesson: FlowBooster.drone,
  ),
  _Plan(
    'Стопка чеков',
    22,
    [FlowGoal('stack', 2), FlowGoal('collect:receipt', 15)],
    stacks: 2,
    lesson: FlowBooster.rocketRow,
  ),
  _Plan(
    'Разбор документов',
    26,
    [FlowGoal('stack', 3), FlowGoal('collect:chart', 20)],
    stacks: 3,
    stackLayers: 2,
    lesson: FlowBooster.bomb,
  ),
  _Plan(
    'Порядок со всех сторон',
    28,
    [FlowGoal('stack', 3), FlowGoal('ice', 2), FlowGoal('collect:wallet', 18)],
    ice: 2,
    stacks: 3,
    stackLayers: 2,
  ),
  _Plan(
    'Перекрёстный поток',
    30,
    [FlowGoal('stack', 3), FlowGoal('ice', 3), FlowGoal('collect:coin', 20)],
    ice: 3,
    stacks: 3,
    combo: (FlowBooster.rocketRow, FlowBooster.rocketColumn),
  ),
  _Plan(
    'Широкий проход',
    30,
    [FlowGoal('stack', 3), FlowGoal('ice', 3), FlowGoal('collect:receipt', 22)],
    ice: 3,
    iceLayers: 2,
    stacks: 3,
    combo: (FlowBooster.rocketRow, FlowBooster.bomb),
  ),
  _Plan(
    'Двойная волна',
    32,
    [FlowGoal('stack', 4), FlowGoal('ice', 2), FlowGoal('collect:goal', 22)],
    ice: 2,
    stacks: 4,
    stackLayers: 2,
    combo: (FlowBooster.bomb, FlowBooster.bomb),
  ),
  _Plan(
    'Ядро и ракета',
    34,
    [FlowGoal('stack', 4), FlowGoal('ice', 4), FlowGoal('collect:shield', 24)],
    ice: 4,
    stacks: 4,
    stackLayers: 2,
    combo: (FlowBooster.core, FlowBooster.rocketRow),
  ),
  _Plan(
    'Сердце первого потока',
    36,
    [
      FlowGoal('stack', 5),
      FlowGoal('ice', 4),
      FlowGoal('collect:coin', 25),
      FlowGoal('collect:chart', 25),
    ],
    ice: 4,
    iceLayers: 2,
    stacks: 5,
    stackLayers: 2,
    combo: (FlowBooster.core, FlowBooster.bomb),
  ),
];

FlowLevel _copy(
  FlowLevel base, {
  List<FlowCell>? board,
  (int, int)? teachingMove,
  String? tutorial,
  int? seed,
}) => FlowLevel(
  id: base.id,
  name: base.name,
  chapterId: base.chapterId,
  seed: seed ?? base.seed,
  moves: base.moves,
  types: base.types,
  obstacles: base.obstacles,
  goals: base.goals,
  scoreThresholds: base.scoreThresholds,
  initialLayout: board ?? base.initialLayout,
  teachingMove: teachingMove ?? base.teachingMove,
  tutorial: tutorial ?? base.tutorial,
);

String _instruction(_Plan p) {
  if (p.combo != null) {
    return 'Обменяйте отмеченные усилители. Сочетание разрешается за один ход; после него выполните все оставшиеся цели.';
  }
  return switch (p.lesson) {
    FlowBooster.rocketRow =>
      'Обменяйте отмеченные клетки: четыре по горизонтали создадут ракету. Затем обменяйте ракету с соседней доступной фишкой, чтобы запустить её.',
    FlowBooster.rocketColumn =>
      'Обменяйте отмеченные клетки: четыре по вертикали создадут ракету. Ракета очищает свой столбец.',
    FlowBooster.bomb =>
      'Обменяйте отмеченные клетки: T-образная фигура создаст Fin-взрыв. Он очищает область 3 × 3.',
    FlowBooster.core =>
      'Обменяйте отмеченные клетки: пять в ряд создадут ядро. Обмен ядра с обычной фишкой очищает её тип.',
    FlowBooster.drone =>
      'Обменяйте отмеченные клетки: квадрат 2 × 2 создаст дрон. При запуске он выбирает нужное препятствие или цель.',
    _ =>
      'Выберите две соседние клетки нажатием или свайпом. Собирайте указанные фишки; неверный обмен не тратит ход.',
  };
}

FlowLevel _build(int id, _Plan plan) {
  const icePositions = [10, 14, 49, 54, 1, 62];
  const stackPositions = [8, 15, 48, 55, 61, 6];
  final obstacles = <FlowObstacle>[
    for (var i = 0; i < plan.ice; i++)
      FlowObstacle(icePositions[i], 'ice', plan.iceLayers),
    for (var i = 0; i < plan.stacks; i++)
      FlowObstacle(stackPositions[i], 'stack', plan.stackLayers),
  ];
  for (var attempt = 0; attempt < 500; attempt++) {
    final seed = 100000 + id * 1009 + attempt * 97;
    final base = FlowLevel(
      id: id,
      name: plan.name,
      seed: seed,
      moves: plan.moves,
      obstacles: obstacles,
      goals: plan.goals,
      scoreThresholds: [0, 400 + id * 55, 850 + id * 90],
      tutorial: _instruction(plan),
    );
    var board = List<FlowCell>.of(FlowEngine.newGame(base).board);
    (int, int)? teaching;
    if (plan.lesson != null) {
      const a = FlowTile.coin, b = FlowTile.wallet;
      List<int> same;
      var source = 19, dest = 27;
      switch (plan.lesson!) {
        case FlowBooster.rocketRow:
          same = [25, 26, 28];
        case FlowBooster.rocketColumn:
          same = [11, 19, 35];
          source = 26;
        case FlowBooster.core:
          same = [25, 26, 28, 29];
        case FlowBooster.bomb:
          same = [26, 28, 35, 43];
        case FlowBooster.drone:
          same = [28, 35, 36];
        case FlowBooster.none:
          same = [];
      }
      for (final i in same) {
        board[i] = const FlowCell(tile: a);
      }
      board[source] = const FlowCell(tile: a);
      board[dest] = const FlowCell(tile: b);
      teaching = (source, dest);
    } else if (plan.combo != null) {
      teaching = (27, 28);
      final (first, second) = plan.combo!;
      board[27] = FlowCell(
        tile: first == FlowBooster.core ? null : board[27].tile,
        booster: first,
      );
      board[28] = FlowCell(
        tile: second == FlowBooster.core ? null : board[28].tile,
        booster: second,
      );
    } else {
      final initial = FlowEngine.newGame(base);
      final moves = FlowEngine.legalMoves(initial);
      var best = -1.0;
      for (final m in moves) {
        final turn = FlowEngine.swap(base, initial, m.$1, m.$2);
        final value = _value(base, turn.session);
        if (value > best) {
          best = value;
          teaching = m;
        }
      }
      // Store the exact initial layout, so a tutorial is invariant if generation
      // tuning changes later. Its fill RNG still starts from the level seed.
      board = List.of(initial.board);
    }
    final level = _copy(base, board: board, teachingMove: teaching);
    try {
      FlowLevels.validate(level);
      if (plan.lesson != null) {
        final turn = FlowEngine.swap(
          level,
          FlowEngine.newGame(level),
          teaching!.$1,
          teaching.$2,
        );
        if (!turn.events.any(
          (e) => e.kind == 'create' && e.booster == plan.lesson,
        )) {
          continue;
        }
      }
      return level;
    } on Object {
      continue;
    }
  }
  throw StateError('Cannot create stable instructional level$id');
}

double _value(FlowLevel level, FlowSession s) {
  var score = 0.0;
  for (final goal in level.goals) {
    final value = (s.progress[goal.key] ?? 0).clamp(0, goal.target);
    score += value / goal.target * 10000;
  }
  score += s.board.where((c) => c.booster != FlowBooster.none).length * 15;
  score += s.score * .002;
  if (s.status == FlowStatus.won) score += 1000000;
  return score;
}

class _Path {
  const _Path(this.session, this.moves);
  final FlowSession session;
  final List<(int, int)> moves;
}

_Path? _solve(FlowLevel level) {
  final initial = FlowEngine.newGame(level);
  var paths = [_Path(initial, [])];
  if (level.teachingMove != null) {
    final first = level.teachingMove!;
    final result = FlowEngine.swap(level, initial, first.$1, first.$2);
    if (!result.accepted) throw StateError('Bad teaching move');
    if (result.session.status == FlowStatus.won) {
      return _Path(result.session, [first]);
    }
    paths = [
      _Path(result.session, [first]),
    ];
  }
  const beamWidth = 6;
  for (var depth = paths.first.moves.length; depth < level.moves; depth++) {
    final next = <_Path>[];
    final seen = <String>{};
    for (final path in paths) {
      final legal = FlowEngine.legalMoves(path.session);
      for (final move in legal) {
        final turn = FlowEngine.swap(level, path.session, move.$1, move.$2);
        if (!turn.accepted) continue;
        final candidate = _Path(turn.session, [...path.moves, move]);
        if (candidate.session.status == FlowStatus.won) return candidate;
        if (candidate.session.status != FlowStatus.active) continue;
        final key =
            '${candidate.session.rngState}:${candidate.session.progress}:${candidate.session.board.map((c) => '${c.tile?.index}${c.booster.index}${c.ice}${c.stack}').join()}';
        if (seen.add(key)) next.add(candidate);
      }
    }
    if (next.isEmpty) return null;
    next.sort((a, b) {
      final cmp = _value(level, b.session).compareTo(_value(level, a.session));
      if (cmp != 0) return cmp;
      return a.moves.last.$1.compareTo(b.moves.last.$1);
    });
    paths = next.take(beamWidth).toList();
  }
  return null;
}

void _verify() {
  final levels = FlowLevels.decode(File(_catalogPath).readAsStringSync());
  if (levels.length != 20 ||
      !List.generate(
        20,
        (i) => i + 1,
      ).every((id) => levels.any((l) => l.id == id))) {
    throw StateError('Expected 20 actual levels');
  }
  final root = jsonDecode(File(_replayPath).readAsStringSync()) as Map;
  if (root['schemaVersion'] != 1) throw StateError('Invalid replay schema');
  final replays = (root['levels'] as List).cast<Map>();
  if (replays.length != 20) throw StateError('Expected 20 replays');
  for (final level in levels) {
    final replay = replays.singleWhere((r) => r['levelId'] == level.id);
    if (replay['seed'] != level.seed) throw StateError('Replay seed mismatch');
    var state = FlowEngine.newGame(level);
    var index = 0;
    for (final raw in replay['moves'] as List) {
      final move = raw as List;
      if (index == 0 &&
          level.teachingMove != null &&
          (move[0] != level.teachingMove!.$1 ||
              move[1] != level.teachingMove!.$2)) {
        throw StateError('Replay must begin with teaching move on ${level.id}');
      }
      final turn = FlowEngine.swap(
        level,
        state,
        move[0] as int,
        move[1] as int,
      );
      if (!turn.accepted) {
        throw StateError('Invalid replay move on ${level.id}');
      }
      final lesson = _plans[level.id - 1].lesson;
      if (index == 0 &&
          lesson != null &&
          !turn.events.any(
            (event) => event.kind == 'create' && event.booster == lesson,
          )) {
        throw StateError('Teaching move did not create $lesson on ${level.id}');
      }
      state = turn.session;
      index++;
    }
    if (state.status != FlowStatus.won ||
        state.score != replay['score'] ||
        state.stars(level) != replay['stars']) {
      throw StateError('Unconfirmed level ${level.id}');
    }
    stdout.writeln(
      'Verified level ${level.id}: ${(replay['moves'] as List).length}/${level.moves} moves, score ${state.score}, stars ${state.stars(level)}',
    );
  }
}

void main(List<String> args) {
  if (args.contains('--verify')) {
    _verify();
    return;
  }
  final levels = <FlowLevel>[], replays = <Map<String, Object?>>[];
  for (var i = 0; i < _plans.length; i++) {
    final level = _build(i + 1, _plans[i]);
    final solution = _solve(level);
    if (solution == null) {
      throw StateError(
        'Level${level.id} not solved within${level.moves} moves',
      );
    }
    levels.add(level);
    replays.add({
      'levelId': level.id,
      'seed': level.seed,
      'moves': solution.moves.map((m) => [m.$1, m.$2]).toList(),
      'score': solution.session.score,
      'stars': solution.session.stars(level),
    });
    stdout.writeln(
      'Solved ${level.id} ${level.name}: ${solution.moves.length}/${level.moves}, score${solution.session.score}',
    );
  }
  const encoder = JsonEncoder.withIndent('  ');
  File(_catalogPath).writeAsStringSync(
    '${encoder.convert({'schemaVersion': 1, 'levels': levels.map((l) => l.toJson()).toList()})}\n',
  );
  File(_replayPath).writeAsStringSync(
    '${encoder.convert({'schemaVersion': 1, 'levels': replays})}\n',
  );
  final out = StringBuffer('# Finora — Поток: первые 20 уровней\n\n');
  out.writeln(
    '20 отдельных определений, шесть типов фишек, постепенное введение усилителей и препятствий. Числа — рабочий прототипный баланс, а не финальная настройка 500 уровней.\n',
  );
  out.writeln(
    'Для каждого уровня проверен хотя бы один выигрышный маршрут с реальными правилами движка. Это подтверждает существование прохождения, но не доказывает удобство, сложность или вероятность победы для человека.\n',
  );
  out.writeln(
    '| Уровень | Название | Цели | Лимит | Прохождение | Счёт | Звёзды | Seed |',
  );
  out.writeln('|---|---|---|---:|---:|---:|---:|---:|');
  for (var i = 0; i < levels.length; i++) {
    final l = levels[i], r = replays[i];
    out.writeln(
      '|${l.id}|${l.name}|${l.goals.map((g) => '${g.title}:${g.target}').join('; ')}|${l.moves}|${(r['moves'] as List).length}|${r['score']}|${r['stars']}|${l.seed}|',
    );
  }
  out.writeln(
    '\nУчебные поля 4–10, 12–14 имеют гарантированный первый ход для создания нужной фигуры. Поля 16–20 содержат готовую пару усилителей для обучения сочетаниям; другие фишки остаются обычными. Все начальные поля стабильны, готовых совпадений нет. Подсказка — реальные индексы клеток, не картинка.\n',
  );
  out.writeln(
    'Клетки индексируются от 0 до 63 по строкам 8 × 8. Для каждого прохождения сохранены seed, последовательность обменов, итоговые счёт и звёзды в `assets/flow/winning_replays.json`. Начальная раскладка также зафиксирована в определении уровня.\n',
  );
  out.writeln(
    'Воспроизведение: `source tool/cloud_env.sh`, затем `dart run tool/solve_flow.dart --verify`. Пересборка набора и поиск доказательных прохождений: `dart run tool/solve_flow.dart`. Поиск ограничен числом ходов и шириной луча 6; отсутствие решения приводит к ошибке, а не к заявлению о готовности.\n',
  );
  out.writeln(
    'Дальше: проверка сложности реальными игроками, финальные рисунки фишек, 50 и 500 уровней, остальные препятствия и FinoraPower. Эти пункты здесь не реализованы.',
  );
  File('docs/FLOW_BALANCE.md').writeAsStringSync(out.toString());
  _verify();
}
