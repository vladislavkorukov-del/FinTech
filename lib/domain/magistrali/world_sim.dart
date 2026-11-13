part of 'world.dart';

/// The fixed step: production once a game day, trucks every tick.
extension MagWorldSim on MagWorld {
  /// Runs [n] ticks (the screen calls it with the elapsed time × speed).
  void step([int n = 1]) {
    for (var i = 0; i < n; i++) {
      _tick();
    }
  }

  void _tick() {
    tick++;
    if (tick % MagRules.ticksPerDay == 0) _day();
    for (final v in vehicles.values.toList()) {
      switch (v.state) {
        case MagVehicleState.garage:
        case MagVehicleState.idle:
          break;
        case MagVehicleState.noRoad:
          if (--v.wait <= 0) _tryStart(v);
        case MagVehicleState.driving:
          _drive(v);
        case MagVehicleState.atStop:
          _atStop(v);
      }
    }
  }

  int get day => tick ~/ MagRules.ticksPerDay;

  void _day() {
    for (final i in map.industries) {
      // Processing first, so delivered goods turn into new cargo.
      var budget = MagRules.processPerDay;
      for (final e in i.spec.converts.entries) {
        final have = i.input[e.key] ?? 0;
        final room = MagRules.outputCap - (i.stock[e.value] ?? 0);
        final n = math.min(math.min(have, budget), room);
        if (n <= 0) continue;
        budget -= n;
        i.input[e.key] = have - n;
        i.stock[e.value] = (i.stock[e.value] ?? 0) + n;
        destroyed[e.key] = (destroyed[e.key] ?? 0) + n;
        created[e.value] = (created[e.value] ?? 0) + n;
      }
      for (final e in i.spec.produces.entries) {
        final room = MagRules.outputCap - (i.stock[e.key] ?? 0);
        final n = math.min(e.value, room);
        if (n <= 0) continue;
        i.stock[e.key] = (i.stock[e.key] ?? 0) + n;
        created[e.key] = (created[e.key] ?? 0) + n;
      }
    }
    // Upkeep: trucks and roads.
    var upkeep = 0;
    for (final v in vehicles.values) {
      upkeep += upkeepOf(v);
    }
    if (upkeep > 0) _spend(upkeep, 'upkeep');
    var roadUpkeep = 0;
    for (final r in roads) {
      if (r != 0) roadUpkeep += MagRules.roads[MagRoad.values[r]]!.upkeep;
    }
    if (roadUpkeep >= 10) _spend(roadUpkeep ~/ 10, 'roads_upkeep');
    if (day % MagRules.daysPerMonth == 0) {
      months.add(MagMonth(day ~/ MagRules.daysPerMonth));
      if (months.length > 12) months.removeAt(0);
    }
  }

  /// Where a truck drives: its order's place, or its route's next stop.
  MagIndustry? _target(MagVehicle v) =>
      v.orderId != null ? _orderTarget(v) : _stopOf(v, v.stop);

  /// A truck without a job any more stops being driven.
  void _lost(MagVehicle v) {
    if (v.orderId == null) return _park(v);
    final o = _orderOf(v);
    if (o != null && o.status.active) {
      _closeOrder(o, MagOrderStatus.failed, 'Предприятие недоступно');
    } else {
      v
        ..orderId = null
        ..state = v.onMap ? MagVehicleState.idle : MagVehicleState.garage;
    }
  }

  MagIndustry? _stopOf(MagVehicle v, int index) {
    final r = routes[v.routeId];
    if (r == null || r.stops.isEmpty) return null;
    return map.industry(r.stops[index % r.stops.length]);
  }

  /// Puts a truck on the map at its route's first stop, or plans its way
  /// on. Without a road it waits and tries again.
  void _tryStart(MagVehicle v) {
    final target = _target(v);
    if (target == null) return _lost(v);
    if (!v.onMap) {
      final access = accessCells(target);
      if (access.isEmpty) {
        v
          ..state = MagVehicleState.noRoad
          ..wait = MagRules.retryTicks;
        _orderNoRoad(v);
        return;
      }
      _orderStarted(v);
      v
        ..cell = access.first
        ..path = const []
        ..progress = 0;
      _arrive(v);
      return;
    }
    _plan(v);
  }

  void _plan(MagVehicle v) {
    final target = _target(v);
    if (target == null) return _lost(v);
    // From a stop a truck may leave by any road reaching that place.
    // (It stands at the place when its cell touches the last stop.)
    final last = v.orderId != null ? null : _stopOf(v, v.stop - 1);
    final yard = v.orderId != null
        ? _yardAround(v.cell)
        : last != null && _touches(v.cell, last)
        ? accessCells(last)
        : const <int>[];
    final path = roadPath([v.cell, ...yard], target);
    if (path == null) {
      v
        ..state = MagVehicleState.noRoad
        ..path = const []
        ..progress = 0
        ..wait = MagRules.retryTicks;
      _orderNoRoad(v);
      return;
    }
    _orderStarted(v);
    v
      ..cell = path.first
      ..path = path
      ..pathIndex = 0
      ..progress = 0
      ..wait = roadVersion
      ..state = MagVehicleState.driving;
    if (path.length == 1) _arrive(v);
  }

  void _drive(MagVehicle v) {
    // Roads changed since the plan: plan again from the next cell boundary.
    if (v.wait != roadVersion && v.progress == 0) {
      _plan(v);
      if (v.state != MagVehicleState.driving) return;
    }
    var dist = speedOf(v) * wearFactor(v) / MagRules.ticksPerSecond;
    while (dist > 0 && v.state == MagVehicleState.driving) {
      final next = v.path[v.pathIndex + 1];
      v.dir = _dirTo(v.cell, next);
      final roadK = math.max(_roadSpeed(next), .4);
      final need = (1 - v.progress) / roadK;
      if (dist < need) {
        v.progress += dist * roadK;
        break;
      }
      dist -= need;
      v
        ..pathIndex += 1
        ..cell = next
        ..progress = 0
        ..odometer += 1
        ..wear = math.min(100, v.wear + wearRateOf(v))
        ..unpaid += runningCostOf(v);
      if (v.unpaid >= 1) {
        final n = v.unpaid.floor();
        v.unpaid -= n;
        _spend(n, 'running');
      }
      if (v.pathIndex == v.path.length - 1) {
        _arrive(v);
      } else if (v.wait != roadVersion) {
        _plan(v);
      }
    }
  }

  int _dirTo(int from, int to) {
    final d = to - from;
    if (d == 1) return 1;
    if (d == -1) return 3;
    return d > 0 ? 2 : 0;
  }

  /// At a stop: deliver what this place takes (paid now, once), then load.
  void _arrive(MagVehicle v) {
    final here = _target(v);
    if (here == null) return _lost(v);
    if (v.orderId != null) return _orderArrive(v, here);
    v
      ..state = MagVehicleState.atStop
      ..wait = 0
      ..path = const []
      ..progress = 0;
    if (autoService && v.wear >= 50 && money >= serviceCost(v)) {
      _spend(serviceCost(v), 'service');
      v.wear = 0;
    }
    if (v.load > 0 && here.spec.accepts.contains(v.cargo)) _deliver(v, here);
  }

  void _deliver(MagVehicle v, MagIndustry here) {
    final cargo = v.cargo!, n = v.load;
    final from = map.industry(v.loadFrom ?? -1);
    final dist = math.max(
      MagRules.minPayDistance,
      from == null ? 0 : from.distanceTo(here),
    );
    final pay = (n * MagRules.cargoRate[cargo]! * dist).round();
    if (here.spec.converts.containsKey(cargo)) {
      here.input[cargo] = (here.input[cargo] ?? 0) + n;
    } else {
      destroyed[cargo] = (destroyed[cargo] ?? 0) + n; // towns use it up
    }
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
    _earn(pay, 'delivery');
    delivered[cargo] = (delivered[cargo] ?? 0) + n;
    deliveries++;
    month.deliveries++;
    _gainXp(math.max(1, pay ~/ 10));
    _countContracts(cargo, here.id, n);
    _say('+$pay кр · ${here.name}');
    _checkTasks();
  }

  /// Cargo this stop can hand to the truck: made here and taken by
  /// another stop of the route.
  MagCargo? _loadable(MagVehicle v, MagIndustry here) {
    final r = routes[v.routeId]!;
    final wanted = <MagCargo>{};
    for (final id in r.stops) {
      if (id == here.id) continue;
      wanted.addAll(map.industry(id)?.spec.accepts ?? const {});
    }
    if (v.load > 0) {
      return here.supplies.contains(v.cargo) && wanted.contains(v.cargo)
          ? v.cargo
          : null;
    }
    MagCargo? best;
    for (final c in here.supplies) {
      if (!wanted.contains(c)) continue;
      if (best == null || availableOf(here, c) > availableOf(here, best)) {
        best = c;
      }
    }
    return best;
  }

  void _atStop(MagVehicle v) {
    if (v.orderId != null) return _orderAtStop(v);
    final here = _stopOf(v, v.stop);
    if (here == null) return _park(v);
    v.wait++;
    final cargo = _loadable(v, here);
    final cap = capacityOf(v);
    if (cargo != null && v.load < cap) {
      // Cargo reserved by orders is not for route trucks.
      final have = availableOf(here, cargo);
      final n = math.min(math.min(MagRules.handlePerTick, cap - v.load), have);
      if (n > 0) {
        here.stock[cargo] = (here.stock[cargo] ?? 0) - n;
        if (v.load == 0) {
          v
            ..cargo = cargo
            ..loadFrom = here.id;
        }
        v.load += n;
      }
    }
    if (v.wait < MagRules.minStopTicks) return;
    final full = v.load >= cap;
    final waitedLong =
        v.wait >= MagRules.partialWaitDays * MagRules.ticksPerDay;
    // Stay while there is cargo to wait for: until full, or with a part
    // load after a while; an empty truck waits for its first unit.
    if (cargo != null && !full && (v.load == 0 || !waitedLong)) return;
    final r = routes[v.routeId]!;
    v.stop = (v.stop + 1) % r.stops.length;
    _plan(v);
  }

  /// Vehicle position in cells (centre of its cell plus progress).
  (double, double) positionOf(MagVehicle v) {
    final x = cx(v.cell) + .5, y = cy(v.cell) + .5;
    if (v.state != MagVehicleState.driving ||
        v.pathIndex + 1 >= v.path.length) {
      return (x, y);
    }
    final n = v.path[v.pathIndex + 1];
    return (
      x + (cx(n) + .5 - x) * v.progress,
      y + (cy(n) + .5 - y) * v.progress,
    );
  }
}
