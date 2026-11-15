part of 'world.dart';

/// Ways by road (S20: kept apart so the world's own file stays short):
/// a quick refusal by connected pieces, then A*, and remembered legs.
extension MagWorldPaths on MagWorld {
  /// The quickest way by road from any of [from] to any stop of [to]. A
  /// place joins all roads that reach it, so a truck leaving a stop may
  /// start from any of its stop cells.
  List<int>? roadPath(List<int> from, MagIndustry to) {
    from = [
      for (final c in from)
        if (roadOpen(c)) c, // S23: broken cells are closed
    ];
    if (from.isEmpty) return null;
    if (!_roadReaches(from, to)) return null;
    // The same leg asked again on unchanged roads: the remembered way.
    final key = '${to.id}|${factor(MagBonus.roadSpeed)}|${from.join(',')}';
    final known = _pathCache[key];
    if (known != null) return List.of(known);
    final l = to.left, r = to.right, t = to.top, b = to.bottom;
    final found = magAStar(
      width: size,
      height: size,
      starts: from,
      isGoal: (c) => _touches(c, to),
      step: (a, b) => roadOpen(b) ? 1 / _roadSpeed(b) : null,
      links: spanLinks(), // S28: bridges and overpasses
      cuts: spanCuts(),
      heuristic: (c) {
        final x = cx(c), y = cy(c);
        final dx = math.max(0, math.max(l - x, x - r));
        final dy = math.max(0, math.max(t - y, y - b));
        return math.max(0, dx + dy - 1) / (1.6 * factor(MagBonus.roadSpeed));
      },
    );
    if (found != null) {
      if (_pathCache.length > 400) _pathCache.clear();
      _pathCache[key] = found;
    }
    return found == null ? null : List.of(found);
  }

  /// Can a road from [from] reach [to] at all? (S20: a quick check by
  /// connected pieces of the road network, rebuilt when roads change.)
  bool _roadReaches(List<int> from, MagIndustry to) {
    var sum = roadVersion;
    for (var c = 0; c < roads.length; c++) {
      if (roads[c] != 0) sum = (sum * 31 + c * 7 + roads[c]) & 0x3fffffff;
    }
    for (final c in damaged.keys) {
      sum = (sum * 17 + c + 1) & 0x3fffffff;
    }
    if (sum != _roadCompKey || _roadComp == null) {
      _roadCompKey = sum;
      _pathCache.clear();
      _roadComp = magComponents(
        size,
        size,
        roadOpen,
        links: spanLinks(),
        cuts: spanCuts(),
      );
    }
    final comp = _roadComp!;
    final pieces = {for (final c in from) comp[c]};
    for (var y = to.top - 1; y <= to.bottom + 1; y++) {
      for (var x = to.left - 1; x <= to.right + 1; x++) {
        if (!map.inside(x, y)) continue;
        final c = cellOf(x, y);
        if (comp[c] >= 0 && pieces.contains(comp[c]) && _touches(c, to)) {
          return true;
        }
      }
    }
    return false;
  }
}
