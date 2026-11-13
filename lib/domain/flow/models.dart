/// Deterministic match-3 state. No Flutter, financial models or network access.
enum FlowTile { coin, wallet, goal, shield, receipt, chart }

/// 1.62: twenty hand-made levels, then generated ones up to 500.
const flowLevelCount = 500;

enum FlowBooster { none, rocketRow, rocketColumn, bomb, core, drone }

enum FlowStatus { active, won, lost }

/// Consumables are separate from special pieces earned on the board.
enum FlowTool { hammer, bomb, shuffle, extraMoves }

abstract final class FlowToolRules {
  // One finite introduction allowance per profile, never renewed on restart.
  static const initialStock = {
    FlowTool.hammer: 2,
    FlowTool.bomb: 1,
    FlowTool.shuffle: 1,
    FlowTool.extraMoves: 1,
  };
  static const prelevel = {
    FlowTool.bomb,
    FlowTool.shuffle,
    FlowTool.extraMoves,
  };
  static const extraMoves = 5;
}

class FlowCell {
  const FlowCell({
    this.tile,
    this.booster = FlowBooster.none,
    this.ice = 0,
    this.stack = 0,
    this.chain = 0,
    this.crate = 0,
    this.wall = false,
  });
  final FlowTile? tile;
  final FlowBooster booster;
  final int ice, stack, chain, crate;

  /// 1.62: a wall — a cell that is not part of the board. Nothing moves
  /// into, out of or through it, and nothing breaks it.
  final bool wall;
  bool get movable =>
      !wall &&
      stack == 0 &&
      crate == 0 &&
      ice == 0 &&
      chain == 0 &&
      (tile != null || booster == FlowBooster.core);
  bool get empty =>
      !wall &&
      stack == 0 &&
      crate == 0 &&
      tile == null &&
      booster == FlowBooster.none;

  /// Cells that stay put while pieces fall: walls and blocking obstacles.
  bool get fixed => wall || stack > 0 || ice > 0 || chain > 0 || crate > 0;
  Map<String, Object?> toJson() => {
    'tile': tile?.name,
    'booster': booster.name,
    'ice': ice,
    'stack': stack,
    if (chain > 0) 'chain': chain,
    if (crate > 0) 'crate': crate,
    if (wall) 'wall': true,
  };
  factory FlowCell.fromJson(Map<String, dynamic> j) {
    _keys(j, {'tile', 'booster', 'ice', 'stack', 'chain', 'crate', 'wall'});
    final tile = j['tile'] == null
        ? null
        : FlowTile.values.byName(j['tile'] as String);
    final b = FlowBooster.values.byName(j['booster'] as String? ?? 'none');
    final ice = _int(j['ice'] ?? 0, 0, 5), stack = _int(j['stack'] ?? 0, 0, 5);
    final chain = _int(j['chain'] ?? 0, 0, 2),
        crate = _int(j['crate'] ?? 0, 0, 2);
    final wall = j['wall'] ?? false;
    if (wall is! bool) throw const FormatException('Invalid flow cell');
    if (wall) {
      if (tile != null ||
          b != FlowBooster.none ||
          ice > 0 ||
          stack > 0 ||
          chain > 0 ||
          crate > 0) {
        throw const FormatException('Invalid flow cell');
      }
      return const FlowCell(wall: true);
    }
    if ((stack > 0 || crate > 0) &&
            (tile != null || b != FlowBooster.none || ice > 0 || chain > 0) ||
        stack > 0 && crate > 0 ||
        chain > 0 && ice > 0 ||
        chain > 0 && tile == null ||
        b == FlowBooster.core && tile != null ||
        ice > 0 && tile == null ||
        b != FlowBooster.none && b != FlowBooster.core && tile == null) {
      throw const FormatException('Invalid flow cell');
    }
    return FlowCell(
      tile: tile,
      booster: b,
      ice: ice,
      stack: stack,
      chain: chain,
      crate: crate,
    );
  }
}

class FlowGoal {
  const FlowGoal(this.key, this.target);
  final String key;
  final int target;
  String get title => switch (key) {
    'ice' => 'Разбить лёд',
    'stack' => 'Разобрать чеки',
    'chain' => 'Снять цепи',
    'crate' => 'Разобрать ящики',
    'collect:coin' => 'Монеты C',
    'collect:wallet' => 'Кошельки W',
    'collect:goal' => 'Цели G',
    'collect:shield' => 'Щиты S',
    'collect:receipt' => 'Чеки R',
    'collect:chart' => 'Графики H',
    _ => key,
  };
  Map<String, Object?> toJson() => {'key': key, 'target': target};
  factory FlowGoal.fromJson(Map<String, dynamic> j) {
    _keys(j, {'key', 'target'});
    final key = j['key'] as String;
    if (!{
      'ice',
      'stack',
      'chain',
      'crate',
      ...FlowTile.values.map((t) => 'collect:${t.name}'),
    }.contains(key)) {
      throw const FormatException('Unsupported flow goal');
    }
    return FlowGoal(key, _int(j['target'], 1, 10000));
  }
}

class FlowObstacle {
  const FlowObstacle(this.index, this.kind, this.layers);
  final int index, layers;
  final String kind;
  Map<String, Object?> toJson() => {
    'index': index,
    'kind': kind,
    'layers': layers,
  };
  factory FlowObstacle.fromJson(Map<String, dynamic> j) {
    _keys(j, {'index', 'kind', 'layers'});
    final kind = j['kind'] as String;
    if (!{'ice', 'stack', 'chain', 'crate', 'wall'}.contains(kind)) {
      throw const FormatException('Unsupported flow obstacle');
    }
    return FlowObstacle(
      _int(j['index'], 0, 63),
      kind,
      _int(
        j['layers'],
        1,
        kind == 'wall'
            ? 1
            : {'chain', 'crate'}.contains(kind)
            ? 2
            : 5,
      ),
    );
  }
}

class FlowLevel {
  const FlowLevel({
    required this.id,
    this.chapterId = 1,
    required this.name,
    required this.seed,
    required this.moves,
    this.types = FlowTile.values,
    this.obstacles = const [],
    required this.goals,
    required this.scoreThresholds,
    this.initialLayout,
    this.tutorial = '',
    this.teachingMove,
  });
  final int id, chapterId, seed, moves;
  final String name, tutorial;
  final List<FlowTile> types;
  final List<FlowObstacle> obstacles;
  final List<FlowGoal> goals;
  final List<int> scoreThresholds;
  final List<FlowCell>? initialLayout;
  final (int, int)? teachingMove;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'chapterId': chapterId,
    'name': name,
    'width': 8,
    'height': 8,
    'seed': seed,
    'moves': moves,
    'availableTileTypes': types.map((e) => e.name).toList(),
    'obstacles': obstacles.map((e) => e.toJson()).toList(),
    'goals': goals.map((e) => e.toJson()).toList(),
    'scoreThresholds': scoreThresholds,
    if (initialLayout != null)
      'initialLayout': initialLayout!.map((e) => e.toJson()).toList(),
    'tutorial': tutorial,
    if (teachingMove != null)
      'teachingMove': [teachingMove!.$1, teachingMove!.$2],
  };
  factory FlowLevel.fromJson(Map<String, dynamic> j) {
    _keys(j, {
      'schemaVersion',
      'id',
      'chapterId',
      'name',
      'width',
      'height',
      'seed',
      'moves',
      'availableTileTypes',
      'obstacles',
      'goals',
      'scoreThresholds',
      'initialLayout',
      'tutorial',
      'teachingMove',
    });
    if (j['schemaVersion'] != 1 || j['width'] != 8 || j['height'] != 8) {
      throw const FormatException('Only flow schema1,8x8 supported');
    }
    final types = (j['availableTileTypes'] as List)
        .map((e) => FlowTile.values.byName(e as String))
        .toList();
    if (types.length < 3 || types.toSet().length != types.length) {
      throw const FormatException('Invalid flow tile types');
    }
    final thresholds = (j['scoreThresholds'] as List)
        .map((e) => _int(e, 0, 10000000))
        .toList();
    if (thresholds.length != 3 ||
        thresholds[0] >= thresholds[1] ||
        thresholds[1] >= thresholds[2]) {
      throw const FormatException('Invalid star thresholds');
    }
    final goals = (j['goals'] as List)
        .map((e) => FlowGoal.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (goals.isEmpty ||
        goals.map((g) => g.key).toSet().length != goals.length) {
      throw const FormatException('Invalid goals');
    }
    final layout = (j['initialLayout'] as List?)
        ?.map((e) => FlowCell.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (layout != null && layout.length != 64) {
      throw const FormatException('Invalid board size');
    }
    final move = j['teachingMove'] as List?;
    if (move != null && move.length != 2) {
      throw const FormatException('Invalid tutorial move');
    }
    return FlowLevel(
      id: _int(j['id'], 1, 500),
      chapterId: _int(j['chapterId'] ?? 1, 1, 10),
      name: j['name'] as String,
      seed: _int(j['seed'], 1, 0xffffffff),
      moves: _int(j['moves'], 1, 100),
      types: types,
      goals: goals,
      obstacles: (j['obstacles'] as List? ?? [])
          .map(
            (e) => FlowObstacle.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      scoreThresholds: thresholds,
      initialLayout: layout,
      tutorial: j['tutorial'] as String? ?? '',
      teachingMove: move == null
          ? null
          : (_int(move[0], 0, 63), _int(move[1], 0, 63)),
    );
  }
}

class FlowSession {
  FlowSession({
    required this.levelId,
    required List<FlowCell> board,
    required this.remainingMoves,
    required this.score,
    required Map<String, int> progress,
    required this.rngState,
    this.status = FlowStatus.active,
    this.bonusMoves = 0,
    Map<FlowTool, int> usedTools = const {},
  }) : board = List.unmodifiable(board),
       progress = Map.unmodifiable(progress),
       usedTools = Map.unmodifiable(usedTools);
  final int levelId, remainingMoves, score, rngState;
  final List<FlowCell> board;
  final Map<String, int> progress;
  final FlowStatus status;
  final int bonusMoves;
  final Map<FlowTool, int> usedTools;
  bool get finished => status != FlowStatus.active;
  int stars(FlowLevel level) => status != FlowStatus.won
      ? 0
      : score >= level.scoreThresholds[2]
      ? 3
      : score >= level.scoreThresholds[1]
      ? 2
      : 1;
  Map<String, Object?> toJson() => {
    'version': 1,
    'levelId': levelId,
    'board': board.map((c) => c.toJson()).toList(),
    'remainingMoves': remainingMoves,
    'score': score,
    'progress': progress,
    'rngState': rngState,
    'status': status.name,
    if (bonusMoves > 0) 'bonusMoves': bonusMoves,
    if (usedTools.isNotEmpty)
      'usedTools': {for (final e in usedTools.entries) e.key.name: e.value},
  };
  factory FlowSession.fromJson(Map<String, dynamic> j) {
    _keys(j, {
      'version',
      'levelId',
      'board',
      'remainingMoves',
      'score',
      'progress',
      'rngState',
      'status',
      'bonusMoves',
      'usedTools',
    });
    if (j['version'] != 1) throw const FormatException('Unsupported session');
    final board = (j['board'] as List)
        .map((e) => FlowCell.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (board.length != 64 ||
        board.any((e) => e.empty) ||
        !_stableBoard(board)) {
      throw const FormatException('Session must be stable and full');
    }
    final progress = <String, int>{};
    for (final e in (j['progress'] as Map).entries) {
      if (!{
        'ice',
        'stack',
        'chain',
        'crate',
        ...FlowTile.values.map((t) => 'collect:${t.name}'),
      }.contains(e.key)) {
        throw const FormatException('Invalid progress');
      }
      progress[e.key as String] = _int(e.value, 0, 1000000);
    }
    return FlowSession(
      levelId: _int(j['levelId'], 1, 500),
      board: board,
      remainingMoves: _int(j['remainingMoves'], 0, 200),
      score: _int(j['score'], 0, 100000000),
      progress: progress,
      rngState: _int(j['rngState'], 1, 0xffffffff),
      status: FlowStatus.values.byName(j['status'] as String),
      bonusMoves: _int(j['bonusMoves'] ?? 0, 0, 100),
      usedTools: _tools(j['usedTools']),
    );
  }
}

class FlowEvent {
  const FlowEvent(
    this.kind,
    this.index, {
    this.tile,
    this.booster,
    this.amount = 1,
    this.chain = 0,
  });
  final String kind;
  final int index, amount, chain;
  final FlowTile? tile;
  final FlowBooster? booster;
}

class FlowTurn {
  const FlowTurn({
    required this.accepted,
    required this.session,
    this.events = const [],
    this.shuffled = false,
  });
  final bool accepted, shuffled;
  final FlowSession session;
  final List<FlowEvent> events;
}

class FlowResult {
  const FlowResult({required this.stars, required this.bestScore});
  final int stars, bestScore;
  Map<String, Object?> toJson() => {'stars': stars, 'bestScore': bestScore};
  factory FlowResult.fromJson(Map<String, dynamic> j) => FlowResult(
    stars: _int(j['stars'], 1, 3),
    bestScore: _int(j['bestScore'], 0, 100000000),
  );
}

const _missing = Object();

class FlowProgress {
  const FlowProgress({
    this.results = const {},
    this.session,
    this.spent = const {},
    this.music = false,
    this.sound = true,
    this.haptics = true,
    this.preferencesSaved = false,
  });
  final Map<int, FlowResult> results;
  final FlowSession? session;
  final Map<FlowTool, int> spent;
  final bool music, sound, haptics, preferencesSaved;
  int available(FlowTool tool) =>
      (FlowToolRules.initialStock[tool]! - (spent[tool] ?? 0)).clamp(
        0,
        FlowToolRules.initialStock[tool]!,
      );
  FlowProgress consume(FlowTool tool) {
    if (available(tool) <= 0) {
      throw const FormatException('Усилитель закончился');
    }
    return copyWith(spent: {...spent, tool: (spent[tool] ?? 0) + 1});
  }

  int get highestUnlocked {
    var n = 1;
    while (n <= flowLevelCount && results.containsKey(n)) {
      n++;
    }
    return n.clamp(1, flowLevelCount);
  }

  bool isUnlocked(int id) =>
      id >= 1 && id <= flowLevelCount && id <= highestUnlocked;
  FlowProgress copyWith({
    Map<int, FlowResult>? results,
    Object? session = _missing,
    Map<FlowTool, int>? spent,
    bool? music,
    bool? sound,
    bool? haptics,
    bool? preferencesSaved,
  }) => FlowProgress(
    results: results ?? this.results,
    session: identical(session, _missing)
        ? this.session
        : session as FlowSession?,
    spent: spent ?? this.spent,
    music: music ?? this.music,
    sound: sound ?? this.sound,
    haptics: haptics ?? this.haptics,
    preferencesSaved: preferencesSaved ?? this.preferencesSaved,
  );
  Map<String, Object?> toJson() => {
    'version': 1,
    'results': {for (final e in results.entries) '${e.key}': e.value.toJson()},
    if (session != null) 'session': session!.toJson(),
    if (spent.isNotEmpty)
      'spent': {for (final e in spent.entries) e.key.name: e.value},
    if (preferencesSaved || music || !sound || !haptics)
      'preferences': {'music': music, 'sound': sound, 'haptics': haptics},
  };
  factory FlowProgress.fromJson(Map<String, dynamic> j) {
    // A damaged optional game session cannot reset unrelated Finance/world data.
    final results = <int, FlowResult>{};
    for (final e
        in (j['results'] is Map ? j['results'] as Map : const {}).entries) {
      final id = int.tryParse('${e.key}');
      if (id == null || id < 1 || id > flowLevelCount) continue;
      try {
        results[id] = FlowResult.fromJson(
          Map<String, dynamic>.from(e.value as Map),
        );
      } on Object {
        continue;
      }
    }
    FlowSession? session;
    try {
      if (j['version'] == 1 && j['session'] is Map) {
        session = FlowSession.fromJson(
          Map<String, dynamic>.from(j['session'] as Map),
        );
      }
    } on Object {
      session = null;
    }
    final prefs = j['preferences'] is Map ? j['preferences'] as Map : const {};
    Map<FlowTool, int> spent;
    try {
      spent = _tools(j['spent']);
    } on Object {
      // Malformed ledger fails closed: it cannot mint another starter allowance.
      spent = Map.of(FlowToolRules.initialStock);
    }
    final progress = FlowProgress(
      results: results,
      spent: spent,
      music: prefs['music'] is bool ? prefs['music'] as bool : false,
      sound: prefs['sound'] is bool ? prefs['sound'] as bool : true,
      haptics: prefs['haptics'] is bool ? prefs['haptics'] as bool : true,
      preferencesSaved: prefs.isNotEmpty,
    );
    if (session != null && !progress.isUnlocked(session.levelId)) {
      session = null;
    }
    return progress.copyWith(session: session);
  }
  FlowProgress record(FlowSession value, FlowLevel level) {
    if (value.levelId != level.id) {
      throw const FormatException('Wrong level result');
    }
    if (value.status != FlowStatus.won) return copyWith(session: value);
    final old = results[level.id];
    final stars = value.stars(level);
    return copyWith(
      session: value,
      results: {
        ...results,
        level.id: FlowResult(
          stars: old == null || stars > old.stars ? stars : old.stars,
          bestScore: old == null || value.score > old.bestScore
              ? value.score
              : old.bestScore,
        ),
      },
    );
  }

  static FlowProgress merge(FlowProgress local, FlowProgress incoming) {
    final results = {...local.results};
    for (final e in incoming.results.entries) {
      final old = results[e.key];
      results[e.key] = FlowResult(
        stars: old == null || e.value.stars > old.stars
            ? e.value.stars
            : old.stars,
        bestScore: old == null || e.value.bestScore > old.bestScore
            ? e.value.bestScore
            : old.bestScore,
      );
    }
    final preferences = local.preferencesSaved ? local : incoming;
    return FlowProgress(
      results: results,
      session: local.session ?? incoming.session,
      spent: {
        for (final tool in FlowTool.values)
          if ((local.spent[tool] ?? 0) > 0 || (incoming.spent[tool] ?? 0) > 0)
            tool: (local.spent[tool] ?? 0) > (incoming.spent[tool] ?? 0)
                ? local.spent[tool]!
                : incoming.spent[tool]!,
      },
      music: preferences.music,
      sound: preferences.sound,
      haptics: preferences.haptics,
      preferencesSaved: preferences.preferencesSaved,
    );
  }
}

Map<FlowTool, int> _tools(Object? raw) {
  if (raw == null) return const {};
  if (raw is! Map) throw const FormatException('Invalid tool ledger');
  return {
    for (final e in raw.entries)
      FlowTool.values.byName(e.key as String): _int(e.value, 0, 1000000),
  };
}

void _keys(Map<String, dynamic> j, Set<String> allowed) {
  if (j.keys.any((k) => !allowed.contains(k))) {
    throw const FormatException('Unsupported flow parameter');
  }
}

int _int(Object? value, int min, int max) {
  if (value is! int || value < min || value > max) {
    throw const FormatException('Invalid flow number');
  }
  return value;
}

bool _stableBoard(List<FlowCell> board) {
  FlowTile? color(int i) =>
      board[i].stack == 0 &&
          board[i].crate == 0 &&
          board[i].booster != FlowBooster.core
      ? board[i].tile
      : null;
  for (var i = 0; i < 64; i++) {
    final tile = color(i);
    if (tile == null) continue;
    if (i % 8 < 6 && color(i + 1) == tile && color(i + 2) == tile) return false;
    if (i < 48 && color(i + 8) == tile && color(i + 16) == tile) return false;
    if (i % 8 < 7 &&
        i < 56 &&
        color(i + 1) == tile &&
        color(i + 8) == tile &&
        color(i + 9) == tile) {
      return false;
    }
  }
  return true;
}
