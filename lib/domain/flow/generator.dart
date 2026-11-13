import 'dart:math' as math;

import 'models.dart';

/// 1.62: levels 21–500, made from their number. The same number always gives
/// the same level, so nothing is stored and progress stays comparable.
///
/// Difficulty grows slowly with small breathers: new obstacles arrive one at
/// a time (walls at 26, chains at 31, crates at 41), counts and layers grow,
/// and every tenth level is a gentler one. Moves come from what the goals
/// ask for, with a margin that narrows as the levels go on.
abstract final class FlowLevelGenerator {
  static const first = 21;
  static const wallsFrom = 26, chainsFrom = 31, cratesFrom = 41;

  /// Levels per chapter: each chapter can get its own backdrop.
  static const chapterSize = 50;
  static int chapterOf(int id) => (id - 1) ~/ chapterSize + 1;

  static List<FlowLevel> all() => [
    for (var id = first; id <= flowLevelCount; id++) generate(id),
  ];

  static FlowLevel generate(int id) => build(id, variants[id] ?? 0);

  /// One layout of level [id]; [variant] picks another when the first one
  /// proved too hard to finish (see [variants]).
  static FlowLevel build(int id, int variant) {
    if (id < first || id > flowLevelCount) {
      throw RangeError.range(id, first, flowLevelCount, 'id');
    }
    final r = _Random(id * 2654435761 + 97 + variant * 40503);
    // 0 at level 21, 1 at level 500.
    final x = (id - first) / (flowLevelCount - first);
    final gentle = id % 10 == 5;

    // Board shape: walls from a mirrored template.
    final walls = <int>{};
    if (id >= wallsFrom && (id == wallsFrom || r.chance(.35 + .4 * x))) {
      final template = id == wallsFrom
          ? _wallTemplates.first
          : _wallTemplates[r.next(_wallTemplates.length)];
      for (final (row, col) in template) {
        walls
          ..add(row * 8 + col)
          ..add(row * 8 + 7 - col);
      }
    }

    // Obstacle kinds this level uses (a newly arrived one is shown alone).
    final unlocked = [
      'ice',
      'stack',
      if (id >= chainsFrom) 'chain',
      if (id >= cratesFrom) 'crate',
    ];
    final List<String> kinds;
    if (id == chainsFrom) {
      kinds = ['chain'];
    } else if (id == cratesFrom) {
      kinds = ['crate'];
    } else if (id == wallsFrom) {
      kinds = [];
    } else {
      final count = gentle
          ? (r.chance(.5) ? 0 : 1)
          : id < 60
          ? r.next(2) + (r.chance(.25) ? 1 : 0)
          : 1 + (r.chance(.35 + .3 * x) ? 1 : 0);
      final pool = List.of(unlocked);
      r.shuffle(pool);
      kinds = pool.take(math.min(count, pool.length)).toList();
    }

    final obstacles = <FlowObstacle>[];
    final taken = {...walls};
    for (final kind in kinds) {
      final target = (4 + x * 8 + r.next(3) - (gentle ? 2 : 0)).round().clamp(
        2,
        12,
      );
      final layers = switch (kind) {
        'ice' => 1 + (r.chance(.2 + .5 * x) ? 1 : 0),
        'stack' => 1 + (r.chance(.25 + .5 * x) ? 1 : 0),
        'chain' => 1 + (id > 80 && r.chance(.15 + .35 * x) ? 1 : 0),
        _ => 1 + (id > 60 && r.chance(.2 + .4 * x) ? 1 : 0),
      };
      // Mirrored pairs keep the board tidy; the top row always feeds it.
      var placed = 0;
      for (var tries = 0; placed < target && tries < 200; tries++) {
        // Rows 1–6, columns 1–6: an edge or the bottom row leaves too few
        // ways to match the last piece.
        final row = 1 + r.next(6), col = 1 + r.next(3);
        final a = row * 8 + col, b = row * 8 + 7 - col;
        if (taken.contains(a) || taken.contains(b)) continue;
        if (!_reachable(a, kind, taken, obstacles, walls) ||
            !_reachable(b, kind, taken, obstacles, walls)) {
          continue;
        }
        for (final i in [a, b]) {
          if (placed >= target) break;
          taken.add(i);
          obstacles.add(FlowObstacle(i, kind, layers));
          placed++;
        }
      }
    }
    for (final w in walls) {
      obstacles.add(FlowObstacle(w, 'wall', 1));
    }

    // Tiles: every tenth level has one colour fewer, which is easier.
    final types = List.of(FlowTile.values);
    if (gentle) types.removeAt(r.next(types.length));

    // Goals: clear the obstacles, and collect one or two colours.
    final goals = <FlowGoal>[
      for (final kind in kinds)
        FlowGoal(kind, obstacles.where((o) => o.kind == kind).length),
    ];
    final collect = kinds.isEmpty
        ? 1 + (r.chance(.35 + .3 * x) ? 1 : 0)
        : r.chance(.75)
        ? 1
        : 0;
    final colours = List.of(types);
    r.shuffle(colours);
    for (final tile in colours.take(collect)) {
      final target =
          (14 + x * 22 + r.next(7) - (gentle ? 4 : 0)) /
          (collect == 2 ? 1.25 : 1);
      goals.add(FlowGoal('collect:${tile.name}', target.round()));
    }
    if (goals.isEmpty) {
      goals.add(FlowGoal('collect:${colours.first.name}', 16));
    }

    // Moves: the work the goals ask for, with a margin that narrows.
    var work = 0.0;
    for (final g in goals) {
      final layers = obstacles
          .where((o) => o.kind == g.key)
          .fold(0, (s, o) => s + o.layers);
      work += switch (g.key) {
        'ice' => layers * 1.5,
        'chain' => layers * 1.7,
        'stack' => layers * 1.6,
        'crate' => layers * 1.7,
        _ => g.target / (types.length == 5 ? 2.3 : 2.0),
      };
    }
    work += walls.length * .3;
    final margin = gentle ? .92 : .82;
    final moves = (work * margin + 5).round().clamp(12, 60);

    final s1 = (moves * (40 + 12 * x) / 5).round() * 5;
    final s2 = (moves * (72 + 20 * x) / 5).round() * 5;

    return FlowLevel(
      id: id,
      chapterId: chapterOf(id),
      name: _name(id, r),
      seed: (id * 7919 + 104729 + variant * 15485863) & 0x7fffffff,
      moves: moves,
      types: types,
      obstacles: obstacles,
      goals: goals,
      scoreThresholds: [0, s1, s2],
      tutorial: switch (id) {
        wallsFrom =>
          'Стенки — часть поля: они не двигаются и не разрушаются. '
              'Новые фишки появляются прямо под ними.',
        chainsFrom =>
          'Фишку в цепях нельзя сдвинуть. Собирайте ряды рядом с ней или '
              'прямо с ней, чтобы снять цепь.',
        cratesFrom =>
          'Ящик разбивается, когда рядом собирается ряд или в него попадает '
              'усилитель.',
        _ => '',
      },
    );
  }

  /// Levels whose first layout a test player could not finish with a fair
  /// margin, and the layout used instead. Regenerate with
  /// `FLOW_CALIBRATE=1 flutter test test/flow_generator_v162_test.dart`.
  static const variants = <int, int>{
    24: 1,
    42: 1,
    44: 1,
    48: 2,
    49: 1,
    50: 1,
    63: 1,
    78: 1,
    83: 1,
    87: 1,
    88: 1,
    89: 1,
    101: 1,
    107: 1,
    114: 1,
    116: 1,
    119: 3,
    124: 1,
    130: 1,
    132: 2,
    137: 1,
    141: 1,
    144: 1,
    149: 1,
    150: 2,
    152: 1,
    153: 1,
    156: 1,
    177: 2,
    183: 1,
    203: 1,
    212: 1,
    217: 1,
    218: 1,
    220: 1,
    223: 3,
    232: 1,
    246: 2,
    249: 2,
    257: 1,
    260: 1,
    263: 1,
    264: 1,
    267: 2,
    279: 1,
    283: 1,
    287: 1,
    290: 1,
    291: 1,
    294: 1,
    297: 2,
    298: 1,
    299: 1,
    306: 1,
    310: 1,
    327: 1,
    337: 1,
    347: 1,
    361: 1,
    368: 1,
    383: 1,
    397: 1,
    412: 1,
    414: 3,
    416: 1,
    419: 2,
    420: 3,
    421: 2,
    422: 1,
    423: 1,
    431: 1,
    432: 1,
    433: 2,
    434: 1,
    441: 1,
    443: 3,
    447: 1,
    448: 2,
    452: 1,
    453: 1,
    461: 2,
    463: 1,
    472: 1,
    473: 1,
    474: 1,
    476: 1,
    477: 1,
    478: 2,
    482: 2,
    494: 1,
    498: 1,
    499: 1,
  };

  /// A frozen or chained piece needs a free neighbour to be matched with.
  static bool _reachable(
    int i,
    String kind,
    Set<int> taken,
    List<FlowObstacle> placed,
    Set<int> walls,
  ) {
    final neighbours = [
      if (i % 8 > 0) i - 1,
      if (i % 8 < 7) i + 1,
      if (i >= 8) i - 8,
      if (i < 56) i + 8,
    ];
    bool blocking(int n) =>
        walls.contains(n) ||
        placed.any(
          (o) => o.index == n && (o.kind == 'stack' || o.kind == 'crate'),
        );
    final open = neighbours.where((n) => !blocking(n)).length;
    // Blocks also must not wall a piece in.
    if (kind == 'stack' || kind == 'crate') {
      for (final n in neighbours) {
        final o = placed.where((o) => o.index == n);
        if (o.isNotEmpty &&
            (o.first.kind == 'ice' || o.first.kind == 'chain')) {
          final around = [
            if (n % 8 > 0) n - 1,
            if (n % 8 < 7) n + 1,
            if (n >= 8) n - 8,
            if (n < 56) n + 8,
          ].where((m) => m != i && !blocking(m)).length;
          if (around == 0) return false;
        }
      }
    }
    return open >= 2;
  }

  /// Left halves (row, column 0–3) of wall patterns; mirrored on use.
  static const _wallTemplates = <List<(int, int)>>[
    [(3, 0), (4, 0)], // side notches
    [(0, 0), (7, 0)], // corners
    [(3, 3), (4, 3)], // centre pillar
    [(0, 0), (0, 1), (1, 0)], // rounded top
    [(7, 0), (7, 1), (6, 0)], // rounded bottom
    [(2, 1), (5, 1)], // four stones
    [(3, 0), (3, 1), (4, 0), (4, 1)], // waist
    [(0, 3), (7, 3)], // top and bottom gates
    [(0, 0), (7, 0), (3, 3), (4, 3)], // corners and pillar
    [(2, 2), (5, 2)], // inner stones
    [(1, 0), (2, 0), (5, 0), (6, 0)], // ribs
  ];

  static const _places = [
    'Сад',
    'Терраса',
    'Заводь',
    'Аллея',
    'Галерея',
    'Мостик',
    'Ротонда',
    'Оранжерея',
    'Лестница',
    'Фонтан',
    'Беседка',
    'Пристань',
  ];
  static const _moods = [
    'тихих монет',
    'лавандового ветра',
    'ясного счёта',
    'жемчужного утра',
    'мятного дождя',
    'золотых листьев',
    'спокойных чеков',
    'лёгкого бюджета',
    'вечерних огней',
    'бережных шагов',
    'первых накоплений',
    'светлых целей',
  ];
  static String _name(int id, _Random r) =>
      '${_places[r.next(_places.length)]} ${_moods[r.next(_moods.length)]}';
}

/// A small deterministic generator (xorshift), independent of the engine's.
class _Random {
  _Random(int seed) : _state = (seed & 0xffffffff) == 0 ? 1 : seed & 0xffffffff;
  int _state;
  int next(int n) {
    var x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    _state = x & 0xffffffff;
    if (_state == 0) _state = 0x2545f491;
    return _state % n;
  }

  bool chance(double p) => next(10000) < p * 10000;
  void shuffle<T>(List<T> values) {
    for (var i = values.length - 1; i > 0; i--) {
      final j = next(i + 1), v = values[i];
      values[i] = values[j];
      values[j] = v;
    }
  }
}
