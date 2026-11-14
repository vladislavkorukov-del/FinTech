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
    if (tick % MagRules.planEveryTicks == 0) _planLogistics();
    if (tick % MagDispatch.everyTicks == 0) dispatch();
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
    _dayTowns();
    _dayCities();
    for (final i in map.industries) {
      // Processing first, so delivered goods turn into new cargo. A level
      // adds output and storage; a recipe may need several inputs per
      // output; nothing is made without its input or beyond the store.
      final k = outputFactor(i), cap = outputCapOf(i);
      var budget = (MagRules.processPerDay * k).round();
      for (final e in i.spec.converts.entries) {
        final ratio = i.spec.ratio[e.key] ?? 1;
        final have = i.input[e.key] ?? 0;
        final room = cap - (i.stock[e.value] ?? 0);
        var n = math.min(math.min(have ~/ ratio, budget), room);
        // Extra inputs (coal for steel) limit it too.
        for (final x in i.spec.extra.entries) {
          n = math.min(n, (i.input[x.key] ?? 0) ~/ x.value);
        }
        if (n <= 0) continue;
        budget -= n;
        i.input[e.key] = have - n * ratio;
        for (final x in i.spec.extra.entries) {
          final used = n * x.value;
          i.input[x.key] = i.input[x.key]! - used;
          if (i.input[x.key] == 0) i.input.remove(x.key);
          destroyed[x.key] = (destroyed[x.key] ?? 0) + used;
        }
        i.stock[e.value] = (i.stock[e.value] ?? 0) + n;
        destroyed[e.key] = (destroyed[e.key] ?? 0) + n * ratio;
        created[e.value] = (created[e.value] ?? 0) + n;
        if (i.owned) {
          i.produced += n;
          final cost = (n * MagRules.processCost).round();
          i.costs += cost;
          _spend(
            cost,
            'production',
            source: 'industry',
            sourceId: i.id,
            cargo: e.value,
            units: n,
          );
        }
      }
      for (final e in i.spec.produces.entries) {
        final room = cap - (i.stock[e.key] ?? 0);
        final n = math.min((e.value * k).round(), room);
        if (n <= 0) continue;
        i.stock[e.key] = (i.stock[e.key] ?? 0) + n;
        created[e.key] = (created[e.key] ?? 0) + n;
        if (i.owned) i.produced += n;
      }
      if (i.owned) {
        final c = upkeepOfIndustry(i);
        i.costs += c;
        _spend(c, 'industry_upkeep', source: 'industry', sourceId: i.id);
      }
    }
    // Fuel and feed of the day, one entry per vehicle.
    for (final v in vehicles.values) {
      final n = v.unpaid.floor();
      if (n > 0) {
        v
          ..unpaid -= n
          ..costs += n;
        routes[v.routeId]?.costs += n;
        _spend(n, 'running', source: 'vehicle', sourceId: v.id);
      }
    }
    // Upkeep: trucks and roads.
    var upkeep = 0;
    for (final v in vehicles.values) {
      upkeep += upkeepOf(v);
      v.costs += upkeepOf(v);
      routes[v.routeId]?.costs += upkeepOf(v);
    }
    if (upkeep > 0) _spend(upkeep, 'upkeep');
    var roadUpkeep = 0;
    for (final r in roads) {
      if (r != 0) roadUpkeep += MagRules.roads[MagRoad.values[r]]!.upkeep;
    }
    roadUpkeep = (roadUpkeep * factor(MagBonus.roadUpkeep)).round();
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
      // A train starts only on a free platform.
      final access = [
        for (final c in _stopCells(v, target))
          if (!v.spec.rail || !occupied.contains(c)) c,
      ];
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
    // (Trains and vessels leave from where they stand, never another berth.)
    final yard = v.orderId != null
        ? _yardAround(v.cell)
        : last != null &&
              !v.spec.rail &&
              !v.spec.water &&
              _atPlace(v, v.cell, last)
        ? _stopCells(v, last)
        : const <int>[];
    var path = _pathFor(v, [v.cell, ...yard], target);
    if (path != null && v.spec.rail && stations.containsKey(v.cell)) {
      path = _departure(v, path, target);
      if (path == null) return;
    }
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
      // A train waits for the track ahead to clear (it never shares a
      // cell with another train).
      if (v.progress == 0 && !_trackClear(v, next)) break;
      // Horses keep their own pace on any surface; trains their own on
      // the track.
      final roadK = v.spec.rail || v.spec.water
          ? 1.0
          : v.spec.horse
          ? math.max(MagRules.horseRoad(MagRoad.values[roads[next]]), .4)
          : math.max(_roadSpeed(next), .4);
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
      if (v.load == 0) v.emptyCells += 1;
      final line = routes[v.routeId];
      if (line != null) {
        line.cells++;
        if (v.load == 0) line.emptyCells++;
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
      v.costs += serviceCost(v);
      routes[v.routeId]?.costs += serviceCost(v);
      _spend(serviceCost(v), 'service');
      v.wear = 0;
    }
    if (v.load > 0 && here.accepts.contains(v.cargo)) {
      // A warehouse takes only what fits (orders keep their own room).
      final limit = here.spec.stores ? _warehouseRoom(here, v.cargo!) : null;
      if (limit != 0) _deliver(v, here, limit: limit);
    }
  }

  /// Unloads [limit] (all by default). Into a warehouse it is an internal
  /// transfer: stored, not paid — the pay comes when the cargo reaches the
  /// place that uses it.
  void _deliver(MagVehicle v, MagIndustry here, {int? limit}) {
    final cargo = v.cargo!;
    final n = limit == null ? v.load : math.min(v.load, limit);
    final from = map.industry(v.loadFrom ?? -1);
    final fromOwn = ownedPlace(from), toOwn = ownedPlace(here);
    // Into an own place: own goods are only moved (a transfer); an
    // independent producer's goods are bought at market price.
    if (toOwn) {
      if (fromOwn) {
        journal.add(
          tick: tick,
          kind: MagEntryKind.transfer,
          category: 'transfer',
          amount: 0,
          source: 'industry',
          sourceId: here.id,
          cargo: cargo,
          units: n,
        );
      } else {
        final cost = (n * MagRules.cargoValue[cargo]!).round();
        if (here.owned) here.costs += cost;
        _spend(
          cost,
          'purchase',
          source: 'industry',
          sourceId: from?.id,
          cargo: cargo,
          units: n,
        );
      }
    }
    if (here.spec.stores) {
      here.stock[cargo] = (here.stock[cargo] ?? 0) + n;
      v.load -= n;
      if (v.load == 0) {
        v
          ..cargo = null
          ..loadFrom = null
          ..trips += 1;
      }
      _say('На склад: ${here.name} +$n');
      _checkTasks();
      return;
    }
    if (toOwn) {
      // Into an own plant: no freight to pay anyone, no outside sale.
      here.input[cargo] = (here.input[cargo] ?? 0) + n;
      v.load -= n;
      if (v.load == 0) {
        v
          ..cargo = null
          ..loadFrom = null;
      }
      v.trips += 1;
      deliveries++;
      month.deliveries++;
      _say('${here.name}: принято $n');
      _checkTasks();
      return;
    }
    final dist = math.max(
      MagRules.minPayDistance,
      from == null ? 0 : from.distanceTo(here),
    );
    // A bigger settlement is a richer market; a city pays more for its own
    // cargo and for the demand of the week.
    final market = marketFactor(here, cargo);
    final pay =
        (n * MagRules.cargoRate[cargo]! * dist * factor(MagBonus.pay) * market)
            .round();
    if (here.spec.takesIn(cargo)) {
      here.input[cargo] = (here.input[cargo] ?? 0) + n;
    } else if (here.town != null) {
      _townReceive(here, cargo, n);
    } else {
      destroyed[cargo] = (destroyed[cargo] ?? 0) + n;
    }
    v.load -= n;
    if (v.load == 0) {
      v
        ..cargo = null
        ..loadFrom = null;
    }
    v
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
      cargo: cargo,
      units: n,
    );
    // Own goods sold to an outside buyer: the goods' price too.
    if (fromOwn) {
      final sale = (n * MagRules.cargoValue[cargo]!).round();
      if (from!.owned) {
        from
          ..revenue += sale
          ..sold += n;
      }
      _earn(
        sale,
        'goods_sale',
        source: 'industry',
        sourceId: from.id,
        cargo: cargo,
        units: n,
      );
    }
    final town = here.town;
    if (town != null) {
      town
        ..revenue +=
            pay + (fromOwn ? (n * MagRules.cargoValue[cargo]!).round() : 0)
        ..delivered += n;
    }
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
      wanted.addAll(map.industry(id)?.accepts ?? const {});
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
      final n = math.min(math.min(handleRate, cap - v.load), have);
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
