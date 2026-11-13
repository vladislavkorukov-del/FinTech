import 'package:finora/domain/flow/flow.dart';

/// A greedy player for checking generated levels: each turn it plays the
/// legal move that advances the goals most (then the score).
({bool won, int used, FlowSession end}) playGreedy(FlowLevel level) {
  var s = FlowEngine.newGame(level);
  var used = 0;
  double value(FlowSession x) {
    var v = 0.0;
    for (final g in level.goals) {
      v += (x.progress[g.key] ?? 0).clamp(0, g.target) / g.target;
    }
    return v * 1000 + x.score / 1000;
  }

  while (s.status == FlowStatus.active) {
    final moves = FlowEngine.legalMoves(s);
    if (moves.isEmpty) {
      s = FlowEngine.ensurePlayable(level, s).session;
      continue;
    }
    // Cells still holding an unmet obstacle goal: without progress, the
    // player works toward them.
    final targets = [
      for (var i = 0; i < 64; i++)
        if (level.goals.any(
          (g) =>
              (s.progress[g.key] ?? 0) < g.target &&
              switch (g.key) {
                'ice' => s.board[i].ice > 0,
                'stack' => s.board[i].stack > 0,
                'chain' => s.board[i].chain > 0,
                'crate' => s.board[i].crate > 0,
                _ => false,
              },
        ))
          i,
    ];
    double near(int a, int b) {
      if (targets.isEmpty) return 0;
      var d = 99;
      for (final t in targets) {
        for (final c in [a, b]) {
          final m = (t ~/ 8 - c ~/ 8).abs() + (t % 8 - c % 8).abs();
          if (m < d) d = m;
        }
      }
      return 10 / (1 + d);
    }

    FlowSession? best;
    var bestValue = -1.0;
    for (final m in moves) {
      final t = FlowEngine.swap(level, s, m.$1, m.$2);
      if (!t.accepted) continue;
      final v = t.session.status == FlowStatus.won
          ? 1e9
          : value(t.session) + near(m.$1, m.$2);
      if (v > bestValue) {
        bestValue = v;
        best = t.session;
      }
    }
    if (best == null) break;
    s = best;
    used++;
  }
  return (won: s.status == FlowStatus.won, used: used, end: s);
}
