import 'dart:collection';

/// A* on a grid of [width]×[height] cells, 4-connected. [step] gives the
/// cost of entering a cell from a neighbour (null: impassable); [heuristic]
/// must never overestimate the remaining cost. Returns the cells from
/// [start] (or the best of [starts]) to the first goal reached, both
/// included, or null.
List<int>? magAStar({
  required int width,
  required int height,
  int? start,
  List<int>? starts,
  required bool Function(int cell) isGoal,
  required double? Function(int from, int to) step,
  required double Function(int cell) heuristic,
  int maxNodes = 1 << 16,

  /// Also the four diagonal neighbours (water: rivers wind diagonally).
  bool diagonal = false,
}) {
  final from = [?start, ...?starts];
  for (final s in from) {
    if (isGoal(s)) return [s];
  }
  final g = HashMap<int, double>();
  final came = HashMap<int, int>();
  final closed = HashSet<int>();
  final open = _Heap();
  for (final s in from) {
    g[s] = 0;
    open.push(s, heuristic(s));
  }
  var expanded = 0;
  while (open.isNotEmpty) {
    final cur = open.pop();
    if (!closed.add(cur)) continue;
    if (isGoal(cur)) {
      final path = <int>[cur];
      var c = cur;
      while (came.containsKey(c)) {
        c = came[c]!;
        path.add(c);
      }
      return path.reversed.toList();
    }
    if (++expanded > maxNodes) return null;
    final cx = cur % width, cy = cur ~/ width;
    for (var d = 0; d < (diagonal ? 8 : 4); d++) {
      final nx = cx + const [0, 1, 0, -1, 1, 1, -1, -1][d];
      final ny = cy + const [-1, 0, 1, 0, -1, 1, 1, -1][d];
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
      final n = ny * width + nx;
      if (closed.contains(n)) continue;
      final cost = step(cur, n);
      if (cost == null) continue;
      final ng = g[cur]! + cost;
      if (ng < (g[n] ?? double.infinity)) {
        g[n] = ng;
        came[n] = cur;
        open.push(n, ng + heuristic(n));
      }
    }
  }
  return null;
}

/// A binary min-heap of (cell, priority); ties go to the cell pushed first,
/// so paths are deterministic.
class _Heap {
  final _cells = <int>[];
  final _prio = <double>[];
  final _order = <int>[];
  var _counter = 0;
  bool get isNotEmpty => _cells.isNotEmpty;

  bool _less(int a, int b) =>
      _prio[a] < _prio[b] || _prio[a] == _prio[b] && _order[a] < _order[b];

  void _swap(int a, int b) {
    final c = _cells[a], p = _prio[a], o = _order[a];
    _cells[a] = _cells[b];
    _prio[a] = _prio[b];
    _order[a] = _order[b];
    _cells[b] = c;
    _prio[b] = p;
    _order[b] = o;
  }

  void push(int cell, double prio) {
    _cells.add(cell);
    _prio.add(prio);
    _order.add(_counter++);
    var i = _cells.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (!_less(i, parent)) break;
      _swap(i, parent);
      i = parent;
    }
  }

  int pop() {
    final top = _cells.first;
    final last = _cells.length - 1;
    _swap(0, last);
    _cells.removeLast();
    _prio.removeLast();
    _order.removeLast();
    var i = 0;
    while (true) {
      final l = 2 * i + 1, r = l + 1;
      var m = i;
      if (l < _cells.length && _less(l, m)) m = l;
      if (r < _cells.length && _less(r, m)) m = r;
      if (m == i) break;
      _swap(i, m);
      i = m;
    }
    return top;
  }
}
