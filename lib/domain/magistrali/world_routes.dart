part of 'world.dart';

/// Long lines with orders per stop (S13), workers at businesses (PASS-05)
/// and road traffic (ROAD-08, ROAD-10).
extension MagWorldRoutes on MagWorld {
  // ---- Orders at the stops of a line ----

  /// Sets what happens at stop [index] of route [id]: [pick] — load only
  /// this cargo; [noPick] — load nothing; [noDrop] — unload nothing.
  String? setStopOrder(
    int id,
    int index, {
    MagCargo? pick,
    bool noPick = false,
    bool noDrop = false,
    bool ifCargo = false,
  }) {
    final r = routes[id];
    if (r == null) return 'Нет такого маршрута';
    if (index < 0 || index >= r.stops.length) return 'Нет такой остановки';
    final here = map.industry(r.stops[index])!;
    if (pick != null && !here.supplies.contains(pick)) {
      return '«${here.name}» не отдаёт этот груз';
    }
    r.pickAt.remove(index);
    r.noPick.remove(index);
    r.noDrop.remove(index);
    r.ifCargo.remove(index);
    if (ifCargo) r.ifCargo.add(index);
    if (pick != null) r.pickAt[index] = pick;
    if (noPick) r.noPick.add(index);
    if (noDrop) r.noDrop.add(index);
    return null;
  }

  /// The share of the capacity a line's vehicles wait for (ROUTE-06).
  String? setMinLoad(int id, int percent) {
    final r = routes[id];
    if (r == null) return 'Нет такого маршрута';
    if (percent < 0 || percent > 100) return 'От 0 до 100%';
    r.minLoad = percent;
    return null;
  }

  /// The next stop to drive to: stops visited only when needed
  /// (ROUTE-10) are passed by when there is nothing to load or unload.
  int _nextStop(MagVehicle v, MagRoute r) {
    final n = r.stops.length;
    var next = (v.stop + 1) % n;
    for (var guard = 0; guard < n - 1; guard++) {
      if (!r.ifCargo.contains(next) || _needed(v, r, next)) break;
      next = (next + 1) % n;
    }
    return next;
  }

  bool _needed(MagVehicle v, MagRoute r, int index) {
    final here = map.industry(r.stops[index]);
    if (here == null) return false;
    if (v.load > 0 &&
        !r.noDrop.contains(index) &&
        here.accepts.contains(v.cargo)) {
      return true;
    }
    if (v.load >= capacityOf(v)) return false;
    final c = _loadableAt(v, here, index);
    return c != null && availableOf(here, c) > 0;
  }

  /// Cargo this stop can hand to the vehicle: what its orders allow, made
  /// here and taken by another stop of the route.
  MagCargo? _loadable(MagVehicle v, MagIndustry here) =>
      _loadableAt(v, here, v.stop);

  MagCargo? _loadableAt(MagVehicle v, MagIndustry here, int index) {
    final r = routes[v.routeId]!;
    if (r.noPick.contains(index)) return null;
    final only = r.pickAt[index];
    final wanted = <MagCargo>{};
    for (var k = 0; k < r.stops.length; k++) {
      final id = r.stops[k];
      if (id == here.id || r.noDrop.contains(k)) continue;
      wanted.addAll(map.industry(id)?.accepts ?? const {});
    }
    bool ok(MagCargo c) =>
        (only == null || c == only) && wanted.contains(c) && canCarry(v, c);
    if (v.load > 0) {
      return here.supplies.contains(v.cargo) && ok(v.cargo!) ? v.cargo : null;
    }
    final first = _priorityPick(r, here, ok);
    if (first != null) return first;
    MagCargo? best;
    for (final c in here.supplies) {
      if (!ok(c)) continue;
      if (best == null || availableOf(here, c) > availableOf(here, best)) {
        best = c;
      }
    }
    return best;
  }

  /// May the vehicle unload at the stop it reached?
  bool _mayDrop(MagVehicle v) =>
      !(routes[v.routeId]?.noDrop.contains(v.stop) ?? false);

  // ---- Workers (PASS-05) ----

  /// Workers reach a business: they join its staff (raising its output)
  /// and pay their fare.
  void _deliverWorkers(MagVehicle v, MagIndustry here) {
    final n = v.load;
    final from = map.industry(v.loadFrom ?? -1);
    final dist = math.max(
      MagRules.minPayDistance,
      from == null ? 0 : from.distanceTo(here),
    );
    final pay =
        (n *
                MagRules.cargoRate[MagCargo.workers]! *
                dist *
                factor(MagBonus.pay) *
                v.spec.comfort)
            .round();
    here.staff += n;
    destroyed[MagCargo.workers] = (destroyed[MagCargo.workers] ?? 0) + n;
    v
      ..load = 0
      ..cargo = null
      ..loadFrom = null
      ..income += pay
      ..trips += 1;
    final r = routes[v.routeId];
    if (r != null) {
      r.income += pay;
      r.deliveries++;
    }
    _earn(
      pay,
      'delivery',
      source: 'vehicle',
      sourceId: v.id,
      cargo: MagCargo.workers,
      units: n,
    );
    delivered[MagCargo.workers] = (delivered[MagCargo.workers] ?? 0) + n;
    deliveries++;
    month.deliveries++;
    _gainXp(math.max(1, pay ~/ 10));
    _say('${here.name}: +$n работников');
    _checkTasks();
  }

  // ---- Traffic (ROAD-08, ROAD-10) ----

  /// Vehicles that entered [cell] yesterday (the day's load of the road).
  int trafficOf(int cell) => traffic[cell] ?? 0;

  /// Yesterday's load of a road cell against its capacity (1 = full).
  double loadOf(int cell) {
    final r = MagRoad.values[roads[cell]];
    if (r == MagRoad.none) return 0;
    return trafficOf(cell) / MagRules.roads[r]!.capacity;
  }

  /// Speed on a crowded road cell: full speed up to its capacity, then
  /// slower — down to half at three times the capacity.
  double congestionOf(int cell) {
    final l = loadOf(cell);
    return l <= 1 ? 1 : math.max(.5, 1 / (1 + (l - 1) * .5));
  }

  void _countTraffic(MagVehicle v, int cell) {
    _atDepot(v, cell);
    if (v.spec.rail || v.spec.water || v.spec.air || roads[cell] == 0) return;
    trafficToday[cell] = (trafficToday[cell] ?? 0) + 1;
  }

  /// The day ends: today's traffic becomes the load; staff fade.
  void _dayTrafficAndStaff() {
    traffic
      ..clear()
      ..addAll(trafficToday);
    trafficToday.clear();
    for (final i in map.industries) {
      if (i.staff <= 0) continue;
      i.staff *= MagRules.staffFade;
      if (i.staff < .5) i.staff = 0;
    }
  }

  // ---- Saves ----

  Map<String, Object> _saveExtras() => {
    ..._saveMeta(),
    ..._saveWorks(),
    ..._saveComplex(),
    ..._saveNetwork(),
    ..._saveRivals(),
    ..._saveFinish(),
    ..._saveBiomes(),
    ..._saveAir(),
    ..._saveSeasons(),
    ..._saveMarket(),
    if (map.industries.any((i) => i.staff > 0))
      'staff': {
        for (final i in map.industries)
          if (i.staff > 0) '${i.id}': i.staff,
      },
    if (routes.values.any(_hasPlan))
      'routePlans': {
        for (final r in routes.values)
          if (_hasPlan(r))
            '${r.id}': {
              if (r.priority.isNotEmpty)
                'priority': [for (final c in r.priority) c.name],
              if (r.since != 0) 'since': r.since,
              if (r.minLoad != 100) 'minLoad': r.minLoad,
              if (r.ifCargo.isNotEmpty) 'ifCargo': r.ifCargo.toList()..sort(),
            },
      },
    if (routes.values.any(
      (r) => r.pickAt.isNotEmpty || r.noPick.isNotEmpty || r.noDrop.isNotEmpty,
    ))
      'stopOrders': {
        for (final r in routes.values)
          if (r.pickAt.isNotEmpty || r.noPick.isNotEmpty || r.noDrop.isNotEmpty)
            '${r.id}': {
              'pick': {
                for (final e in r.pickAt.entries) '${e.key}': e.value.name,
              },
              'noPick': r.noPick.toList()..sort(),
              'noDrop': r.noDrop.toList()..sort(),
            },
      },
    if (traffic.isNotEmpty)
      'traffic': {for (final e in traffic.entries) '${e.key}': e.value},
    if (trafficToday.isNotEmpty)
      'trafficToday': {
        for (final e in trafficToday.entries) '${e.key}': e.value,
      },
  };

  /// Reads what S13 added to a save (all optional).
  void loadExtras(Map<String, dynamic> j) {
    loadAir(j); // S22: before the vehicles that stand on airports
    loadMeta(j);
    loadWorks(j);
    loadComplex(j);
    int cellOfKey(Object k) {
      final c = int.tryParse('$k');
      if (c == null || c < 0 || c >= size * size) {
        throw const FormatException('Bad cell in Magistrali save');
      }
      return c;
    }

    for (final e in (j['staff'] as Map? ?? const {}).entries) {
      final i = map.industry(int.tryParse('${e.key}') ?? -1);
      final v = e.value;
      if (i == null || v is! num || v < 0 || v > 1e9) {
        throw const FormatException('Bad staff in Magistrali save');
      }
      i.staff = v.toDouble();
    }
    for (final e in (j['stopOrders'] as Map? ?? const {}).entries) {
      final r = routes[int.tryParse('${e.key}') ?? -1];
      final m = e.value;
      if (r == null || m is! Map) {
        throw const FormatException('Bad stop orders in Magistrali save');
      }
      int index(Object k) {
        final n = int.tryParse('$k');
        if (n == null || n < 0 || n >= r.stops.length) {
          throw const FormatException('Bad stop in Magistrali save');
        }
        return n;
      }

      for (final p in (m['pick'] as Map? ?? const {}).entries) {
        r.pickAt[index(p.key)] = MagCargo.values.byName(p.value as String);
      }
      r.noPick.addAll([
        for (final k in m['noPick'] as List? ?? const []) index(k),
      ]);
      r.noDrop.addAll([
        for (final k in m['noDrop'] as List? ?? const []) index(k),
      ]);
    }
    for (final e in (j['routePlans'] as Map? ?? const {}).entries) {
      final r = routes[int.tryParse('${e.key}') ?? -1];
      final m = e.value;
      if (r == null || m is! Map) {
        throw const FormatException('Bad route plan in Magistrali save');
      }
      for (final c in m['priority'] as List? ?? const []) {
        r.priority.add(MagCargo.values.byName(c as String));
      }
      final min = m['minLoad'] ?? 100;
      if (min is! int || min < 0 || min > 100) {
        throw const FormatException('Bad route plan in Magistrali save');
      }
      r.minLoad = min;
      for (final k in m['ifCargo'] as List? ?? const []) {
        if (k is! int || k < 0 || k >= r.stops.length) {
          throw const FormatException('Bad route plan in Magistrali save');
        }
        r.ifCargo.add(k);
      }
      final since = m['since'];
      if (since != null) {
        if (since is! int || since < 0) {
          throw const FormatException('Bad route plan in Magistrali save');
        }
        r.since = since;
      }
    }
    for (final (key, into) in [
      ('traffic', traffic),
      ('trafficToday', trafficToday),
    ]) {
      for (final e in (j[key] as Map? ?? const {}).entries) {
        final v = e.value;
        if (v is! int || v < 0) {
          throw const FormatException('Bad traffic in Magistrali save');
        }
        into[cellOfKey(e.key)] = v;
      }
    }
  }

  bool _hasPlan(MagRoute r) =>
      r.priority.isNotEmpty ||
      r.since != 0 ||
      r.minLoad != 100 ||
      r.ifCargo.isNotEmpty;
}
