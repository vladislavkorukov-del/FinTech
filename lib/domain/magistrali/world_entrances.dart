part of 'world.dart';

/// One way in (S12, 1.83): a business, warehouse or centre is reached
/// through a single road cell next to it — its entrance. The first road
/// built up to it makes the entrance; the player can move it from the
/// road's sheet. Other roads may pass along its side without a way in.
/// Settlements keep every road on their edge.
extension MagWorldEntrances on MagWorld {
  /// Road cells on the edge of [i] (sides, not corners).
  List<int> edgeRoads(MagIndustry i) {
    final out = <int>[];
    for (var y = i.y - 1; y <= i.y + i.size; y++) {
      for (var x = i.x - 1; x <= i.x + i.size; x++) {
        final edge =
            (x == i.x - 1 || x == i.x + i.size) !=
            (y == i.y - 1 || y == i.y + i.size);
        if (edge && hasRoad(x, y)) out.add(cellOf(x, y));
      }
    }
    return out;
  }

  /// The entrance of [i]: the one kept, while its road is there; else
  /// the first road on its edge (null: no road reaches it).
  int? entranceOf(MagIndustry i) {
    final edges = edgeRoads(i);
    if (edges.isEmpty) return null;
    final e = entrances[i.id];
    return e != null && edges.contains(e) ? e : edges.first;
  }

  /// Places (not settlements) whose edge [cell] is on.
  List<MagIndustry> placesBeside(int cell) => [
    for (final i in map.industries)
      if (i.town == null && edgeRoadsContains(i, cell)) i,
  ];

  bool edgeRoadsContains(MagIndustry i, int cell) {
    final x = cx(cell), y = cy(cell);
    final ex = x == i.x - 1 || x == i.x + i.size;
    final ey = y == i.y - 1 || y == i.y + i.size;
    final inX = x >= i.x && x < i.x + i.size;
    final inY = y >= i.y && y < i.y + i.size;
    return ex && inY || ey && inX;
  }

  /// A new road: a place it touches first gets its entrance where the
  /// road reaches it.
  void _noteEntrances(List<int> cells) {
    for (final c in cells) {
      for (final i in placesBeside(c)) {
        final e = entrances[i.id];
        if (e == null || roads[e] == 0 || !edgeRoadsContains(i, e)) {
          entrances[i.id] = c;
        }
      }
    }
  }

  /// Makes [cell] the entrance of [placeId] (from the road's sheet).
  String? setEntrance(int placeId, int cell) {
    final i = map.industry(placeId);
    if (i == null || i.town != null) return 'Здесь нет предприятия';
    if (roads[cell] == 0 || !edgeRoadsContains(i, cell)) {
      return 'Въезд — дорога у стороны предприятия';
    }
    entrances[placeId] = cell;
    roadVersion++;
    _say('Въезд к «${i.name}» перенесён');
    return null;
  }

  /// Reads the entrances of a save. A save from before 1.83 has none: each
  /// place gets the edge road on the biggest road network, so the routes
  /// it ran keep running.
  void loadEntrances(Object? raw) {
    if (raw is Map) {
      for (final e in raw.entries) {
        final id = int.tryParse('${e.key}');
        final c = e.value;
        if (id == null || c is! int || c < 0 || c >= size * size) {
          throw const FormatException('Bad entrance');
        }
        entrances[id] = c;
      }
      return;
    }
    // Label the road networks and their sizes.
    final net = List<int>.filled(size * size, -1);
    final sizes = <int>[];
    for (var s = 0; s < size * size; s++) {
      if (roads[s] == 0 || net[s] >= 0) continue;
      final id = sizes.length;
      var n = 0;
      final stack = [s];
      net[s] = id;
      while (stack.isNotEmpty) {
        final c = stack.removeLast();
        n++;
        for (var d = 0; d < 4; d++) {
          final x = cx(c) + MagDir.dx[d], y = cy(c) + MagDir.dy[d];
          if (!map.inside(x, y)) continue;
          final o = cellOf(x, y);
          if (roads[o] != 0 && net[o] < 0) {
            net[o] = id;
            stack.add(o);
          }
        }
      }
      sizes.add(n);
    }
    for (final i in map.industries) {
      if (i.town != null) continue;
      final edges = edgeRoads(i);
      if (edges.isEmpty) continue;
      edges.sort((a, b) => sizes[net[b]].compareTo(sizes[net[a]]));
      entrances[i.id] = edges.first;
    }
  }
}
