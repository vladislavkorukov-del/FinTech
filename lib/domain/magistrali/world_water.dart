part of 'world.dart';

/// Water transport (stage S9: SEA-01…SEA-04). Vessels sail river and lake
/// cells (rivers wind diagonally, so a vessel may step diagonally from
/// water to water; bridges are no obstacle). A port is a water cell within
/// [MagRules.portReach] cells of a place and serves it: a vessel moored
/// there loads and unloads exactly as a truck at the gate or a train at a
/// station — one economy, one journal. Vessels run routes whose every stop
/// has a port.
extension MagWorldWater on MagWorld {
  bool get shippingUnlocked => bonus(MagBonus.shipping) > 0;
  bool get shipyardUnlocked => bonus(MagBonus.shipyard) > 0;

  bool isWater(int cell) {
    final t = map.at(cx(cell), cy(cell));
    return t == MagTerrain.river || t == MagTerrain.lake;
  }

  /// Places a port at [cell] could serve (nearest first).
  List<MagIndustry> portTargets(int cell) {
    final x = cx(cell), y = cy(cell);
    const r = MagRules.portReach;
    final out = <MagIndustry>{};
    for (var yy = y - r; yy <= y + r; yy++) {
      for (var xx = x - r; xx <= x + r; xx++) {
        final i = map.industryAt(xx, yy);
        if (i != null && i.kind != MagIndustryKind.logisticsCenter) out.add(i);
      }
    }
    return out.toList()..sort(
      (a, b) => ((a.centerX - x).abs() + (a.centerY - y).abs()).compareTo(
        (b.centerX - x).abs() + (b.centerY - y).abs(),
      ),
    );
  }

  String? portBlocker(int cell, int placeId) {
    if (!shippingUnlocked) {
      return 'Порты откроет технология «Речное судоходство»';
    }
    if (!isWater(cell)) return 'Порт ставится на воду';
    if (ports.containsKey(cell)) return 'Здесь уже порт';
    if (!portTargets(cell).any((i) => i.id == placeId)) {
      return 'Порт должен быть в 2 клетках от предприятия';
    }
    return null;
  }

  String? buildPort(int cell, int placeId) {
    final why = portBlocker(cell, placeId);
    if (why != null) return why;
    if (money < MagRules.portPrice) {
      return 'Не хватает кредитов: нужно ${MagRules.portPrice}';
    }
    _spend(MagRules.portPrice, 'ports', source: 'industry', sourceId: placeId);
    ports[cell] = placeId;
    roadVersion++;
    _say('Порт у «${map.industry(placeId)?.name}» построен');
    return null;
  }

  String? removePort(int cell) {
    if (!ports.containsKey(cell)) return 'Здесь нет порта';
    if (occupied.contains(cell)) return 'У причала стоит судно';
    ports.remove(cell);
    roadVersion++;
    return null;
  }

  /// Port cells serving [i].
  List<int> portCells(MagIndustry i) => [
    for (final e in ports.entries)
      if (e.value == i.id) e.key,
  ]..sort();

  /// The quickest way by water from any of [from] to a port of [to].
  List<int>? waterPath(List<int> from, MagIndustry to) {
    from = from.where(isWater).toList();
    final goals = portCells(to).toSet();
    if (from.isEmpty || goals.isEmpty) return null;
    final gx = cx(goals.first), gy = cy(goals.first);
    return magAStar(
      width: size,
      height: size,
      starts: from,
      diagonal: true,
      isGoal: goals.contains,
      step: (a, b) {
        if (!isWater(b)) return null;
        // A diagonal step is longer.
        return cx(a) != cx(b) && cy(a) != cy(b) ? 1.41 : 1;
      },
      heuristic: (c) =>
          math.max((cx(c) - gx).abs(), (cy(c) - gy).abs()).toDouble(),
    );
  }

  /// Are two places joined by water (port to port)?
  bool waterConnected(MagIndustry a, MagIndustry b) =>
      waterPath(portCells(a), b) != null;

  /// Why a vessel cannot run [routeId] (null: it can).
  String? portRouteBlocker(int routeId) {
    final r = routes[routeId];
    if (r == null) return null;
    for (final id in r.stops) {
      final i = map.industry(id);
      if (i == null || portCells(i).isEmpty) {
        return 'У «${i?.name ?? '—'}» нет порта';
      }
    }
    return null;
  }

  /// Water cells as a mask (for checking saved vessels).
  Uint8List get waterMask {
    final m = Uint8List(size * size);
    for (var c = 0; c < m.length; c++) {
      if (isWater(c)) m[c] = 1;
    }
    return m;
  }
}
