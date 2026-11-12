import 'models.dart';

/// Prototype rules, separated from rendering and future tuning.
abstract final class FlowRules {
  static const matchScore = 10,
      iceScore = 5,
      stackScore = 10,
      boosterScore = 25;
  static const bombRadius = 1, doubleBombRadius = 2;
  static const generationAttempts = 180,
      shuffleAttempts = 240,
      cascadeLimit = 128;
}

class FlowMatch {
  const FlowMatch(this.cells, this.booster, this.position);
  final Set<int> cells;
  final FlowBooster booster;
  final int? position;
}

class FlowDiagnostic implements Exception {
  const FlowDiagnostic(this.message);
  final String message;
  @override
  String toString() => 'FlowDiagnostic: $message';
}

abstract final class FlowEngine {
  static void validateSession(FlowLevel level, FlowSession session) {
    FlowSession.fromJson(session.toJson());
    if (session.levelId != level.id ||
        session.remainingMoves > level.moves + session.bonusMoves ||
        session.bonusMoves !=
            (session.usedTools[FlowTool.extraMoves] ?? 0) *
                FlowToolRules.extraMoves ||
        session.board.any(
          (cell) => cell.tile != null && !level.types.contains(cell.tile),
        )) {
      throw const FormatException('Session does not match level');
    }
    final obstacles = {for (final o in level.obstacles) o.index: o};
    for (var i = 0; i < 64; i++) {
      final cell = session.board[i], initial = obstacles[i];
      if (cell.stack > 0 &&
              (initial?.kind != 'stack' || cell.stack > initial!.layers) ||
          cell.ice > 0 &&
              (initial?.kind != 'ice' || cell.ice > initial!.layers) ||
          cell.chain > 0 &&
              (initial?.kind != 'chain' || cell.chain > initial!.layers) ||
          cell.crate > 0 &&
              (initial?.kind != 'crate' || cell.crate > initial!.layers)) {
        throw const FormatException('Moved or inflated obstacle in session');
      }
    }
    for (final kind in ['ice', 'stack', 'chain', 'crate']) {
      final original = level.obstacles.where((o) => o.kind == kind).length;
      final remaining = session.board
          .where(
            (c) => switch (kind) {
              'ice' => c.ice > 0,
              'stack' => c.stack > 0,
              'chain' => c.chain > 0,
              _ => c.crate > 0,
            },
          )
          .length;
      if ((session.progress[kind] ?? 0) + remaining != original) {
        throw const FormatException(
          'Obstacle progress does not match remaining board',
        );
      }
    }
    final won = level.goals.every(
      (g) => (session.progress[g.key] ?? 0) >= g.target,
    );
    final expected = won
        ? FlowStatus.won
        : session.remainingMoves == 0
        ? FlowStatus.lost
        : FlowStatus.active;
    if (session.status != expected ||
        session.status == FlowStatus.active && _legal(session.board).isEmpty) {
      throw const FormatException('Invalid stable session result');
    }
  }

  static bool neighbors(int a, int b) =>
      a >= 0 &&
      b >= 0 &&
      a < 64 &&
      b < 64 &&
      ((a ~/ 8 == b ~/ 8 && (a - b).abs() == 1) || (a - b).abs() == 8);
  static FlowSession newGame(FlowLevel level) {
    final rng = _Rng(level.seed);
    List<FlowCell> board;
    if (level.initialLayout != null) {
      board = List.of(level.initialLayout!);
    } else {
      board = _generate(level, rng);
    }
    if (board.length != 64 ||
        board.any((c) => c.empty) ||
        detect(board).isNotEmpty ||
        _legal(board).isEmpty) {
      throw const FlowDiagnostic('Initial board must be stable and playable');
    }
    return FlowSession(
      levelId: level.id,
      board: board,
      remainingMoves: level.moves,
      score: 0,
      progress: {},
      rngState: rng.state,
    );
  }

  static List<(int, int)> legalMoves(FlowSession session) =>
      session.finished ? [] : _legal(session.board);

  static FlowTurn ensurePlayable(FlowLevel level, FlowSession session) {
    if (session.finished || _legal(session.board).isNotEmpty) {
      return FlowTurn(accepted: false, session: session);
    }
    if (detect(session.board).isNotEmpty) {
      throw const FlowDiagnostic('Resolve matches before shuffling');
    }
    final run = _Resolution(
      level,
      List.of(session.board),
      _Rng(session.rngState),
      session.progress,
      session.score,
    );
    run.shuffle();
    return FlowTurn(
      accepted: false,
      shuffled: true,
      events: run.events,
      session: FlowSession(
        levelId: session.levelId,
        board: run.board,
        remainingMoves: session.remainingMoves,
        score: session.score,
        progress: session.progress,
        rngState: run.rng.state,
        status: session.status,
        bonusMoves: session.bonusMoves,
        usedTools: session.usedTools,
      ),
    );
  }

  static List<(int, int)> _legal(List<FlowCell> board) {
    final moves = <(int, int)>[];
    for (var a = 0; a < 64; a++) {
      if (!board[a].movable) continue;
      for (final b in [if (a % 8 < 7) a + 1, if (a ~/ 8 < 7) a + 8]) {
        if (!board[b].movable) continue;
        if (board[a].booster != FlowBooster.none ||
            board[b].booster != FlowBooster.none) {
          moves.add((a, b));
          continue;
        }
        final copy = List<FlowCell>.of(board);
        final x = copy[a];
        copy[a] = copy[b];
        copy[b] = x;
        if (detect(
          copy,
        ).any((m) => m.cells.contains(a) || m.cells.contains(b))) {
          moves.add((a, b));
        }
      }
    }
    return moves;
  }

  static FlowTurn swap(FlowLevel level, FlowSession session, int from, int to) {
    if (session.levelId != level.id ||
        session.finished ||
        session.remainingMoves <= 0 ||
        !neighbors(from, to) ||
        !session.board[from].movable ||
        !session.board[to].movable) {
      return FlowTurn(accepted: false, session: session);
    }
    final board = List<FlowCell>.of(session.board);
    final original = board[from];
    board[from] = board[to];
    board[to] = original;
    final a = board[from], b = board[to];
    final special =
        a.booster != FlowBooster.none || b.booster != FlowBooster.none;
    if (!special &&
        !detect(
          board,
        ).any((m) => m.cells.contains(from) || m.cells.contains(to))) {
      return FlowTurn(accepted: false, session: session);
    }
    final run = _Resolution(
      level,
      board,
      _Rng(session.rngState),
      session.progress,
      session.score,
    );
    if (special) run.special(from, to);
    var rounds = 0;
    while (true) {
      if (++rounds > FlowRules.cascadeLimit) {
        throw const FlowDiagnostic('Cascade safety limit exceeded');
      }
      run.gravity();
      final matches = detect(
        run.board,
        from: rounds == 1 && !special ? from : null,
        to: rounds == 1 && !special ? to : null,
      );
      if (matches.isEmpty) break;
      run.matches(matches);
    }
    final won = level.goals.every(
      (g) => (run.progress[g.key] ?? 0) >= g.target,
    );
    final status = won
        ? FlowStatus.won
        : session.remainingMoves == 1
        ? FlowStatus.lost
        : FlowStatus.active;
    var shuffled = false;
    if (status == FlowStatus.active && _legal(run.board).isEmpty) {
      run.shuffle();
      shuffled = true;
    }
    final next = FlowSession(
      levelId: level.id,
      board: run.board,
      remainingMoves: session.remainingMoves - 1,
      score: run.score,
      progress: run.progress,
      rngState: run.rng.state,
      status: status,
      bonusMoves: session.bonusMoves,
      usedTools: session.usedTools,
    );
    return FlowTurn(
      accepted: true,
      session: next,
      events: List.unmodifiable(run.events),
      shuffled: shuffled,
    );
  }

  /// Inventory is consumed by the repository/controller only after this succeeds.
  /// Tools do not consume a move; all resulting cascades resolve before returning.
  static FlowTurn useTool(
    FlowLevel level,
    FlowSession session,
    FlowTool tool, {
    int? cell,
  }) {
    if (session.levelId != level.id ||
        session.status == FlowStatus.won ||
        session.status == FlowStatus.lost && tool != FlowTool.extraMoves) {
      return FlowTurn(accepted: false, session: session);
    }
    if ((tool == FlowTool.hammer || tool == FlowTool.bomb) &&
        (cell == null || cell < 0 || cell >= 64)) {
      return FlowTurn(accepted: false, session: session);
    }
    final run = _Resolution(
      level,
      List.of(session.board),
      _Rng(session.rngState),
      session.progress,
      session.score,
    );
    var moves = session.remainingMoves, bonus = session.bonusMoves;
    switch (tool) {
      case FlowTool.extraMoves:
        if (bonus + FlowToolRules.extraMoves > 100) {
          return FlowTurn(accepted: false, session: session);
        }
        moves += FlowToolRules.extraMoves;
        bonus += FlowToolRules.extraMoves;
      case FlowTool.shuffle:
        run.shuffle();
      case FlowTool.hammer:
        run.hit({cell!});
        run.drain();
      case FlowTool.bomb:
        run.hit(run.area(cell!, FlowRules.bombRadius));
        run.drain();
    }
    if (tool == FlowTool.hammer || tool == FlowTool.bomb) {
      var rounds = 0;
      while (true) {
        if (++rounds > FlowRules.cascadeLimit) {
          throw const FlowDiagnostic('Cascade safety limit exceeded');
        }
        run.gravity();
        final matches = detect(run.board);
        if (matches.isEmpty) break;
        run.matches(matches);
      }
    }
    final won = level.goals.every(
      (g) => (run.progress[g.key] ?? 0) >= g.target,
    );
    final status = won
        ? FlowStatus.won
        : moves == 0
        ? FlowStatus.lost
        : FlowStatus.active;
    var shuffled = tool == FlowTool.shuffle;
    if (status == FlowStatus.active && _legal(run.board).isEmpty) {
      run.shuffle();
      shuffled = true;
    }
    return FlowTurn(
      accepted: true,
      shuffled: shuffled,
      events: List.unmodifiable(run.events),
      session: FlowSession(
        levelId: level.id,
        board: run.board,
        remainingMoves: moves,
        score: run.score,
        progress: run.progress,
        rngState: run.rng.state,
        status: status,
        bonusMoves: bonus,
        usedTools: {
          ...session.usedTools,
          tool: (session.usedTools[tool] ?? 0) + 1,
        },
      ),
    );
  }

  /// Connected matching figures on one logical board; no board mutation here.
  static List<FlowMatch> detect(List<FlowCell> board, {int? from, int? to}) {
    if (board.length != 64) throw const FlowDiagnostic('Expected8x8 board');
    final groups = <Set<int>>[],
        horizontal = <Set<int>>[],
        vertical = <Set<int>>[],
        squares = <Set<int>>[];
    FlowTile? color(int i) =>
        board[i].stack == 0 &&
            board[i].crate == 0 &&
            board[i].booster != FlowBooster.core
        ? board[i].tile
        : null;
    for (var row = 0; row < 8; row++) {
      var col = 0;
      while (col < 8) {
        final start = col, t = color(row * 8 + col);
        while (col < 8 && t != null && color(row * 8 + col) == t) {
          col++;
        }
        if (col - start >= 3) {
          final set = {for (var c = start; c < col; c++) row * 8 + c};
          horizontal.add(set);
          groups.add(set);
        }
        if (col == start) col++;
      }
    }
    for (var col = 0; col < 8; col++) {
      var row = 0;
      while (row < 8) {
        final start = row, t = color(row * 8 + col);
        while (row < 8 && t != null && color(row * 8 + col) == t) {
          row++;
        }
        if (row - start >= 3) {
          final set = {for (var r = start; r < row; r++) r * 8 + col};
          vertical.add(set);
          groups.add(set);
        }
        if (row == start) row++;
      }
    }
    for (var r = 0; r < 7; r++) {
      for (var c = 0; c < 7; c++) {
        final i = r * 8 + c, t = color(i);
        if (t != null &&
            color(i + 1) == t &&
            color(i + 8) == t &&
            color(i + 9) == t) {
          final s = {i, i + 1, i + 8, i + 9};
          squares.add(s);
          groups.add(s);
        }
      }
    }
    final matched = groups.expand((g) => g).toSet(), components = <Set<int>>[];
    while (matched.isNotEmpty) {
      final queue = [matched.first], component = <int>{};
      final type = color(queue.first);
      while (queue.isNotEmpty) {
        final i = queue.removeLast();
        if (!matched.remove(i)) continue;
        component.add(i);
        for (final n in _adjacent(i)) {
          if (matched.contains(n) && color(n) == type) queue.add(n);
        }
      }
      components.add(component);
    }
    final out = <FlowMatch>[];
    for (final component in components) {
      bool inGroup(Set<int> group) => group.any(component.contains);
      final h = horizontal.where(inGroup).toList(),
          v = vertical.where(inGroup).toList();
      var booster = FlowBooster.none;
      if ([...h, ...v].any((g) => g.length >= 5)) {
        booster = FlowBooster.core;
      } else if (h.isNotEmpty && v.isNotEmpty && component.length >= 5) {
        booster = FlowBooster.bomb;
      } else if (h.any((g) => g.length >= 4)) {
        booster = FlowBooster.rocketRow;
      } else if (v.any((g) => g.length >= 4)) {
        booster = FlowBooster.rocketColumn;
      } else if (squares.any(inGroup)) {
        booster = FlowBooster.drone;
      }
      final eligible =
          component
              .where(
                (i) => board[i].movable && board[i].booster == FlowBooster.none,
              )
              .toList()
            ..sort();
      int? position;
      if (booster != FlowBooster.none && eligible.isNotEmpty) {
        position = to != null && eligible.contains(to)
            ? to
            : from != null && eligible.contains(from)
            ? from
            : eligible.first;
      }
      out.add(
        FlowMatch(
          component,
          position == null ? FlowBooster.none : booster,
          position,
        ),
      );
    }
    out.sort(
      (a, b) => a.cells
          .reduce((x, y) => x < y ? x : y)
          .compareTo(b.cells.reduce((x, y) => x < y ? x : y)),
    );
    return out;
  }

  static List<FlowCell> _generate(FlowLevel level, _Rng rng) {
    final obstacles = {for (final o in level.obstacles) o.index: o};
    for (var attempt = 0; attempt < FlowRules.generationAttempts; attempt++) {
      final board = <FlowCell>[];
      for (var i = 0; i < 64; i++) {
        final o = obstacles[i];
        if (o?.kind == 'stack' || o?.kind == 'crate') {
          board.add(
            o!.kind == 'stack'
                ? FlowCell(stack: o.layers)
                : FlowCell(crate: o.layers),
          );
          continue;
        }
        final candidates = List<FlowTile>.of(level.types);
        rng.mix(candidates);
        FlowTile? chosen;
        for (final tile in candidates) {
          if (i % 8 >= 2 &&
              board[i - 1].tile == tile &&
              board[i - 2].tile == tile) {
            continue;
          }
          if (i >= 16 &&
              board[i - 8].tile == tile &&
              board[i - 16].tile == tile) {
            continue;
          }
          if (i >= 9 &&
              i % 8 > 0 &&
              board[i - 1].tile == tile &&
              board[i - 8].tile == tile &&
              board[i - 9].tile == tile) {
            continue;
          }
          chosen = tile;
          break;
        }
        if (chosen == null) break;
        board.add(
          FlowCell(
            tile: chosen,
            ice: o?.kind == 'ice' ? o!.layers : 0,
            chain: o?.kind == 'chain' ? o!.layers : 0,
          ),
        );
      }
      if (board.length == 64 &&
          detect(board).isEmpty &&
          _legal(board).isNotEmpty) {
        return board;
      }
    }
    throw const FlowDiagnostic(
      'Unable to generate a playable stable board within bounded attempts',
    );
  }
}

class _Rng {
  _Rng(this.state);
  int state;
  int next(int n) {
    var x = state;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    state = x & 0xffffffff;
    if (state == 0) state = 0x9e3779b9;
    return state % n;
  }

  void mix<T>(List<T> values) {
    for (var i = values.length - 1; i > 0; i--) {
      final j = next(i + 1), v = values[i];
      values[i] = values[j];
      values[j] = v;
    }
  }
}

Iterable<int> _adjacent(int i) sync* {
  if (i % 8 > 0) yield i - 1;
  if (i % 8 < 7) yield i + 1;
  if (i >= 8) yield i - 8;
  if (i < 56) yield i + 8;
}

class _Pending {
  const _Pending(this.index, this.booster, this.tile);
  final int index;
  final FlowBooster booster;
  final FlowTile? tile;
}

class _Resolution {
  _Resolution(
    this.level,
    this.board,
    this.rng,
    Map<String, int> old,
    this.score,
  ) : progress = Map.of(old);
  final FlowLevel level;
  final List<FlowCell> board;
  final _Rng rng;
  final Map<String, int> progress;
  int score;
  final events = <FlowEvent>[];
  final _queue = <_Pending>[];
  final _activated = <int>{};
  int _chain = 0;

  void emit(String kind, int index, {FlowTile? tile, FlowBooster? booster}) =>
      events.add(
        FlowEvent(kind, index, tile: tile, booster: booster, chain: _chain),
      );
  void collect(int i, FlowTile? tile) {
    if (tile == null) return;
    final key = 'collect:${tile.name}';
    progress[key] = (progress[key] ?? 0) + 1;
    score += FlowRules.matchScore;
    emit('collect', i, tile: tile);
  }

  void damageStack(int i) {
    final c = board[i];
    if (c.stack <= 0) return;
    board[i] = FlowCell(stack: c.stack - 1);
    score += FlowRules.stackScore;
    emit('stackDamage', i);
    if (c.stack == 1) {
      progress['stack'] = (progress['stack'] ?? 0) + 1;
      emit('stack', i);
    }
  }

  void damageCrate(int i) {
    final c = board[i];
    if (c.crate <= 0) return;
    board[i] = FlowCell(crate: c.crate - 1);
    score += FlowRules.stackScore;
    emit('crateDamage', i);
    if (c.crate == 1) {
      progress['crate'] = (progress['crate'] ?? 0) + 1;
      emit('crate', i);
    }
  }

  void hit(Set<int> cells, {Set<int> immune = const {}}) {
    final stacks = <int>{}, crates = <int>{};
    final ordered = cells.toList()..sort();
    for (final i in ordered) {
      if (i < 0 || i >= 64 || immune.contains(i)) continue;
      final cell = board[i];
      if (cell.stack > 0) {
        stacks.add(i);
        continue;
      }
      if (cell.crate > 0) {
        crates.add(i);
        continue;
      }
      if (cell.chain > 0) {
        board[i] = FlowCell(
          tile: cell.tile,
          booster: cell.booster,
          chain: cell.chain - 1,
        );
        score += FlowRules.iceScore;
        emit('chainDamage', i);
        if (cell.chain == 1) {
          progress['chain'] = (progress['chain'] ?? 0) + 1;
          emit('chain', i);
        }
        continue;
      }
      if (cell.ice > 0) {
        board[i] = FlowCell(
          tile: cell.tile,
          booster: cell.booster,
          ice: cell.ice - 1,
        );
        score += FlowRules.iceScore;
        emit('iceDamage', i);
        if (cell.ice == 1) {
          progress['ice'] = (progress['ice'] ?? 0) + 1;
          emit('ice', i);
        }
        continue;
      }
      if (cell.empty) continue;
      if (cell.booster != FlowBooster.none) {
        if (_activated.add(i)) {
          _queue.add(_Pending(i, cell.booster, cell.tile));
        }
        collect(i, cell.tile);
        board[i] = const FlowCell();
      } else {
        collect(i, cell.tile);
        board[i] = const FlowCell();
        for (final n in _adjacent(i)) {
          if (board[n].stack > 0) stacks.add(n);
          if (board[n].crate > 0) crates.add(n);
        }
      }
    }
    for (final i in stacks) {
      damageStack(i);
    }
    for (final i in crates) {
      damageCrate(i);
    }
  }

  Set<int> row(int i) => {for (var c = 0; c < 8; c++) i ~/ 8 * 8 + c};
  Set<int> column(int i) => {for (var r = 0; r < 8; r++) r * 8 + i % 8};
  Set<int> area(int i, int radius) => {
    for (var r = i ~/ 8 - radius; r <= i ~/ 8 + radius; r++)
      for (var c = i % 8 - radius; c <= i % 8 + radius; c++)
        if (r >= 0 && r < 8 && c >= 0 && c < 8) r * 8 + c,
  };
  void drain() {
    while (_queue.isNotEmpty) {
      final p = _queue.removeAt(0);
      emit('activate', p.index, booster: p.booster);
      switch (p.booster) {
        case FlowBooster.rocketRow:
          hit(row(p.index));
        case FlowBooster.rocketColumn:
          hit(column(p.index));
        case FlowBooster.bomb:
          hit(area(p.index, FlowRules.bombRadius));
        case FlowBooster.core:
          final counts = {
            for (final type in FlowTile.values)
              type: board
                  .where((c) => c.tile == type && c.booster == FlowBooster.none)
                  .length,
          };
          final types = FlowTile.values.toList()
            ..sort((a, b) {
              final n = counts[b]!.compareTo(counts[a]!);
              return n == 0 ? a.index.compareTo(b.index) : n;
            });
          hit({
            for (var i = 0; i < 64; i++)
              if (board[i].tile == types.first) i,
          });
        case FlowBooster.drone:
          final candidates = <int>[];
          for (var i = 0; i < 64; i++) {
            final c = board[i];
            if (level.goals.any(
                      (g) =>
                          g.key == 'ice' && (progress[g.key] ?? 0) < g.target,
                    ) &&
                    c.ice > 0 ||
                level.goals.any(
                      (g) =>
                          g.key == 'stack' && (progress[g.key] ?? 0) < g.target,
                    ) &&
                    c.stack > 0 ||
                level.goals.any(
                      (g) =>
                          g.key == 'chain' && (progress[g.key] ?? 0) < g.target,
                    ) &&
                    c.chain > 0 ||
                level.goals.any(
                      (g) =>
                          g.key == 'crate' && (progress[g.key] ?? 0) < g.target,
                    ) &&
                    c.crate > 0) {
              candidates.add(i);
            }
          }
          if (candidates.isEmpty) {
            for (var i = 0; i < 64; i++) {
              final c = board[i];
              if (c.tile != null &&
                  level.goals.any(
                    (g) =>
                        g.key == 'collect:${c.tile!.name}' &&
                        (progress[g.key] ?? 0) < g.target,
                  )) {
                candidates.add(i);
              }
            }
          }
          if (candidates.isEmpty) {
            for (var i = 0; i < 64; i++) {
              if (board[i].movable && board[i].booster == FlowBooster.none) {
                candidates.add(i);
              }
            }
          }
          if (candidates.isNotEmpty) hit({candidates.first});
        case FlowBooster.none:
          break;
      }
    }
  }

  void matches(List<FlowMatch> matches) {
    _activated.clear();
    _chain++;
    final protected = <int>{};
    for (final m in matches) {
      final at = m.position;
      if (at == null) continue;
      final c = board[at];
      board[at] = FlowCell(
        tile: m.booster == FlowBooster.core ? null : c.tile,
        booster: m.booster,
      );
      protected.add(at);
      score += FlowRules.boosterScore;
      emit('create', at, booster: m.booster);
    }
    hit(matches.expand((m) => m.cells).toSet(), immune: protected);
    drain();
  }

  bool rocket(FlowBooster b) =>
      b == FlowBooster.rocketRow || b == FlowBooster.rocketColumn;
  void consume(int i) {
    final c = board[i];
    _activated.add(i);
    emit('activate', i, booster: c.booster);
    collect(i, c.tile);
    board[i] = const FlowCell();
  }

  void special(int from, int to) {
    final a = board[from], b = board[to], ba = a.booster, bb = b.booster;
    final both = ba != FlowBooster.none && bb != FlowBooster.none;
    if (both && ba == FlowBooster.core && bb == FlowBooster.core) {
      consume(from);
      consume(to);
      hit({for (var i = 0; i < 64; i++) i});
      drain();
      return;
    }
    if (both &&
        (rocket(ba) && rocket(bb) ||
            rocket(ba) && bb == FlowBooster.bomb ||
            rocket(bb) && ba == FlowBooster.bomb ||
            ba == FlowBooster.bomb && bb == FlowBooster.bomb)) {
      consume(from);
      consume(to);
      if (rocket(ba) && rocket(bb)) {
        hit({...row(to), ...column(to)});
      } else if (ba == FlowBooster.bomb && bb == FlowBooster.bomb) {
        hit(area(to, FlowRules.doubleBombRadius));
      } else {
        hit({
          for (var i = 0; i < 64; i++)
            if ((i ~/ 8 - to ~/ 8).abs() <= 1 || (i % 8 - to % 8).abs() <= 1) i,
        });
      }
      drain();
      return;
    }
    if (ba == FlowBooster.core || bb == FlowBooster.core) {
      final core = ba == FlowBooster.core ? from : to,
          other = core == from ? to : from;
      final partner = board[other];
      if (partner.booster == FlowBooster.drone) {
        hit({from, to});
        drain();
        return;
      }
      consume(core);
      if (rocket(partner.booster) || partner.booster == FlowBooster.bomb) {
        final indexes = [
          for (var i = 0; i < 64; i++)
            if (board[i].tile == partner.tile) i,
        ];
        for (final i in indexes) {
          final c = board[i];
          board[i] = FlowCell(
            tile: c.tile,
            booster: partner.booster,
            ice: c.ice,
            chain: c.chain,
          );
        }
        hit(indexes.toSet());
        drain();
        return;
      }
      hit({
        for (var i = 0; i < 64; i++)
          if (board[i].tile == partner.tile) i,
      });
      drain();
      return;
    }
    hit({if (ba != FlowBooster.none) from, if (bb != FlowBooster.none) to});
    drain();
  }

  void gravity() {
    for (var col = 0; col < 8; col++) {
      var end = 7;
      while (end >= 0) {
        final fixed = board[end * 8 + col];
        if (fixed.stack > 0 ||
            fixed.ice > 0 ||
            fixed.chain > 0 ||
            fixed.crate > 0) {
          end--;
          continue;
        }
        var start = end;
        while (start > 0 &&
            board[(start - 1) * 8 + col].stack == 0 &&
            board[(start - 1) * 8 + col].ice == 0 &&
            board[(start - 1) * 8 + col].chain == 0 &&
            board[(start - 1) * 8 + col].crate == 0) {
          start--;
        }
        final cells = <FlowCell>[
          for (var r = end; r >= start; r--)
            if (!board[r * 8 + col].empty) board[r * 8 + col],
        ];
        var n = 0;
        for (var r = end; r >= start; r--) {
          board[r * 8 + col] = n < cells.length
              ? cells[n++]
              : FlowCell(tile: level.types[rng.next(level.types.length)]);
        }
        end = start - 1;
      }
    }
  }

  void shuffle() {
    final indexes = [
      for (var i = 0; i < 64; i++)
        if (board[i].movable) i,
    ];
    final pool = [for (final i in indexes) board[i]];
    for (var attempt = 0; attempt < FlowRules.shuffleAttempts; attempt++) {
      rng.mix(pool);
      for (var n = 0; n < indexes.length; n++) {
        board[indexes[n]] = pool[n];
      }
      if (FlowEngine.detect(board).isEmpty &&
          FlowEngine._legal(board).isNotEmpty) {
        events.add(const FlowEvent('shuffle', -1));
        return;
      }
    }
    // The immutable pre-turn snapshot remains available to the caller. Never
    // silently regenerate away earned boosters or recolor frozen tiles.
    throw const FlowDiagnostic(
      'No legal shuffle within bounded attempts; previous stable session retained',
    );
  }
}
