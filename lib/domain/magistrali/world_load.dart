part of 'world.dart';

/// Reads a saved company (any format this build knows), or throws
/// [FormatException]: every field is checked and the cargo ledger must add
/// up, so a broken file is refused whole.
MagWorld magWorldFromJson(Map<String, dynamic> raw) {
  final j = migrateMagSave(raw);
  int whole(Object? v, int lo, int hi) {
    if (v is! int || v < lo || v > hi) {
      throw const FormatException('Bad number in Magistrali save');
    }
    return v;
  }

  double real(Object? v, double lo, double hi) {
    if (v is! num || v < lo || v > hi) {
      throw const FormatException('Bad number in Magistrali save');
    }
    return v.toDouble();
  }

  Map<MagCargo, int> cargo(Object? v) => {
    for (final e in (v as Map? ?? const {}).entries)
      MagCargo.values.byName(e.key as String): whole(e.value, 0, 1 << 40),
  };

  Map<String, int> money(Object? v) => {
    for (final e in (v as Map? ?? const {}).entries)
      e.key as String: whole(e.value, -(1 << 50), 1 << 50),
  };

  final seed = whole(j['seed'], 0, 0x7fffffff);
  final size = whole(j['size'], 16, 256);
  final mapVersion = whole(j['mapVersion'] ?? 1, 1, 3);
  final w = MagWorld(
    map: MagMap.generate(seed, size: size, version: mapVersion),
  );
  final saved = j['settlements'] as List?;
  if (saved == null) {
    for (final s in w.settlements) {
      s.town!.remember(
        0,
        'Стало поселением: ${s.town!.spec.name} (обновление 1.72)',
      );
    }
  }
  // Settlements come before roads and warehouses, so nothing may lie on
  // their land.
  for (final raw in saved ?? const []) {
    final m = raw as Map;
    final i = w.map.industry(whole(m['id'], 1, 1 << 20));
    final t = i?.town;
    if (t == null) throw const FormatException('Unknown settlement');
    final level = whole(m['level'], 1, MagTowns.maxLevel);
    final cells = [for (final k in m['cells'] as List) whole(k, 0, 1 << 30)];
    if (cells.isEmpty || !cells.contains(MagSettlement.key(i!.x, i.y))) {
      throw const FormatException('Bad settlement land');
    }
    t.cells.clear();
    for (final k in cells) {
      final x = MagSettlement.keyX(k), y = MagSettlement.keyY(k);
      if (!w.map.inside(x, y)) {
        throw const FormatException('Bad settlement land');
      }
      final ground = w.map.at(x, y);
      final other = w.map.industryAt(x, y);
      if (ground == MagTerrain.lake ||
          ground == MagTerrain.river ||
          other != null && other != i) {
        throw const FormatException('Bad settlement land');
      }
      t.cells.add(k);
    }
    t
      ..level = level
      ..population = whole(m['population'], 0, 1 << 40)
      ..specialization = MagSpecialization.values.byName(
        m['specialization'] as String,
      )
      ..reputation = whole(m['reputation'] ?? 0, 0, 1 << 50)
      ..blocked = m['blocked'] as String?;
    t.pantry.addAll(cargo(m['pantry']));
    t.devStock.addAll(cargo(m['dev']));
    for (final s in m['satisfaction'] as List? ?? const []) {
      t.satisfaction.add(real(s, 0, 1));
    }
    for (final e in m['history'] as List? ?? const []) {
      final pair = e as List;
      t.history.add(
        MagTownEvent(whole(pair[0], 0, 1 << 50), pair[1] as String),
      );
    }
  }
  w.tick = whole(j['tick'], 0, 1 << 50);
  w.money = whole(j['money'], -(1 << 50), 1 << 50);
  w.xp = whole(j['xp'], 0, 1 << 50);
  w.nextId = whole(j['nextId'], 1, 1 << 40);
  w.speed = const [0, 1, 2, 4].contains(j['speed']) ? j['speed'] as int : 1;
  w.rng = whole(j['rng'] ?? 1, 0, 0x7fffffff);
  w.roadVersion = whole(j['roadVersion'] ?? 0, 0, 1 << 40);
  for (final t in j['techs'] as List? ?? const []) {
    if (MagTechTree.byId(t as String) == null) {
      throw const FormatException('Unknown technology');
    }
    w.techs.add(t);
  }
  // Built businesses and warehouses stand before roads are read, so no
  // road may lie under one.
  for (final raw in j['built'] as List? ?? const []) {
    final m = raw as Map;
    final kind = MagIndustryKind.values.byName(m['kind'] as String);
    final spec = MagRules.industries[kind]!;
    final id = whole(m['id'], MagRules.builtIdBase, 1 << 40);
    final x = whole(m['x'], 0, size - spec.size);
    final y = whole(m['y'], 0, size - spec.size);
    if (spec.price == 0 || spec.stores || w.map.industry(id) != null) {
      throw const FormatException('Bad building in Magistrali save');
    }
    for (var yy = y; yy < y + spec.size; yy++) {
      for (var xx = x; xx < x + spec.size; xx++) {
        if (!w.map.roadable(xx, yy)) {
          throw const FormatException('Bad building in Magistrali save');
        }
      }
    }
    w.map.industries.add(
      MagIndustry(id: id, kind: kind, x: x, y: y, name: m['name'] as String)
        ..built = true,
    );
  }
  for (final raw in j['warehouses'] as List? ?? const []) {
    final m = raw as Map;
    final x = whole(m['x'], 0, size - 2), y = whole(m['y'], 0, size - 2);
    final id = whole(m['id'], MagRules.warehouseIdBase, 1 << 40);
    for (var yy = y; yy < y + 2; yy++) {
      for (var xx = x; xx < x + 2; xx++) {
        if (!w.map.roadable(xx, yy)) {
          throw const FormatException('Bad warehouse in Magistrali save');
        }
      }
    }
    if (w.map.industry(id) != null) {
      throw const FormatException('Bad warehouse in Magistrali save');
    }
    final wh = MagIndustry(
      id: id,
      kind: MagIndustryKind.warehouse,
      x: x,
      y: y,
      name: m['name'] as String,
    );
    for (final e in (m['rules'] as Map? ?? const {}).entries) {
      final r = e.value as Map;
      final max = r['max'];
      wh.rules[MagCargo.values.byName(e.key as String)] = MagStockRule(
        mode: MagStockMode.values.byName(r['mode'] as String),
        min: whole(r['min'], 0, 1 << 30),
        target: whole(r['target'], 0, 1 << 30),
        max: max == null ? null : whole(max, 0, 1 << 30),
        priority: whole(r['priority'] ?? 1, 0, 2),
      );
    }
    w.map.industries.add(wh);
  }
  final roads = base64Decode(j['roads'] as String);
  if (roads.length != size * size) {
    throw const FormatException('Bad roads in Magistrali save');
  }
  for (var c = 0; c < roads.length; c++) {
    if (roads[c] >= MagRoad.values.length ||
        roads[c] != 0 && !w.map.roadable(c % size, c ~/ size)) {
      throw const FormatException('Bad road in Magistrali save');
    }
    w.roads[c] = roads[c];
  }
  for (final raw in j['industries'] as List? ?? const []) {
    final m = raw as Map;
    final i = w.map.industry(whole(m['id'], 1, 1 << 20));
    if (i == null) throw const FormatException('Unknown industry');
    i.stock.addAll(cargo(m['stock']));
    i.input.addAll(cargo(m['input']));
    i
      ..owned = m['owned'] as bool? ?? false
      ..level = whole(m['level'] ?? 1, 1, MagRules.maxIndustryLevel)
      ..invested = whole(m['invested'] ?? 0, 0, 1 << 50)
      ..revenue = whole(m['revenue'] ?? 0, 0, 1 << 50)
      ..costs = whole(m['costs'] ?? 0, 0, 1 << 50)
      ..produced = whole(m['produced'] ?? 0, 0, 1 << 50)
      ..sold = whole(m['sold'] ?? 0, 0, 1 << 50);
    if (i.owned && (i.town != null || i.spec.stores || i.spec.price == 0)) {
      throw const FormatException('Bad owner in Magistrali save');
    }
  }
  for (final raw in j['routes'] as List? ?? const []) {
    final m = raw as Map;
    final stops = [for (final s in m['stops'] as List) whole(s, 1, 1 << 20)];
    if (stops.length < 2 || stops.any((s) => w.map.industry(s) == null)) {
      throw const FormatException('Bad route in Magistrali save');
    }
    final r =
        MagRoute(
            id: whole(m['id'], 1, w.nextId - 1),
            name: m['name'] as String,
            stops: stops,
          )
          ..income = whole(m['income'] ?? 0, 0, 1 << 50)
          ..deliveries = whole(m['deliveries'] ?? 0, 0, 1 << 40);
    w.routes[r.id] = r;
  }
  final cells = size * size;
  for (final raw in j['vehicles'] as List? ?? const []) {
    final m = raw as Map;
    final model = m['model'] as String;
    if (MagRules.truck(model) == null) {
      throw const FormatException('Unknown truck model');
    }
    final v = MagVehicle(
      id: whole(m['id'], 1, w.nextId - 1),
      model: model,
      name: m['name'] as String,
    );
    final ups = m['upgrades'] as List;
    for (var k = 0; k < 4; k++) {
      v.upgrades[k] = whole(ups[k], 0, MagRules.maxUpgrade);
    }
    v
      ..wear = real(m['wear'], 0, 100)
      ..odometer = real(m['odometer'], 0, 1e15)
      ..income = whole(m['income'], 0, 1 << 50)
      ..trips = whole(m['trips'], 0, 1 << 40)
      ..upgradeSpent = whole(m['upgradeSpent'] ?? 0, 0, 1 << 50)
      ..stop = whole(m['stop'], 0, 1000)
      ..state = MagVehicleState.values.byName(m['state'] as String)
      ..cell = whole(m['cell'], -1, cells - 1)
      ..path = [for (final c in m['path'] as List) whole(c, 0, cells - 1)]
      ..pathIndex = whole(m['pathIndex'], 0, 1 << 20)
      ..progress = real(m['progress'], 0, 1)
      ..dir = whole(m['dir'], 0, 3)
      ..wait = whole(m['wait'], -(1 << 40), 1 << 40)
      ..unpaid = real(m['unpaid'], 0, 1e6);
    final route = m['route'];
    if (route != null) {
      if (!w.routes.containsKey(route)) {
        throw const FormatException('Truck on an unknown route');
      }
      v.routeId = route as int;
      v.stop %= w.routes[route]!.stops.length;
    }
    if (m['load'] != null) {
      v
        ..cargo = MagCargo.values.byName(m['cargo'] as String)
        ..load = whole(m['load'], 1, 1 << 20)
        ..loadFrom = m['loadFrom'] as int?;
    }
    v.auto = m['auto'] as bool? ?? false;
    final order = m['order'];
    if (order != null) {
      if (route != null) {
        throw const FormatException('Truck on a route and an order');
      }
      v.orderId = whole(order, 1, w.nextId - 1);
    }
    final driving = v.state == MagVehicleState.driving;
    final idle = v.state == MagVehicleState.idle;
    if (v.state != MagVehicleState.garage &&
            !idle &&
            v.routeId == null &&
            v.orderId == null ||
        idle && (!v.onMap || v.routeId != null || v.orderId != null) ||
        driving && v.pathIndex + 1 >= v.path.length ||
        v.onMap && w.roads[v.cell] == 0 ||
        driving && v.path.any((c) => w.roads[c] == 0)) {
      throw const FormatException('Inconsistent truck in Magistrali save');
    }
    w.vehicles[v.id] = v;
  }
  for (final raw in j['orders'] as List? ?? const []) {
    final m = raw as Map;
    final o =
        MagOrder(
            id: whole(m['id'], 1, w.nextId - 1),
            cargo: MagCargo.values.byName(m['cargo'] as String),
            amount: whole(m['amount'], 1, 1 << 20),
            supplier: whole(m['from'], 1, 1 << 20),
            receiver: whole(m['to'], 1, 1 << 20),
            priority: whole(m['priority'] ?? 1, 0, 2),
            createdTick: whole(m['created'] ?? 0, 0, 1 << 50),
            tag: m['tag'] as String?,
            status: MagOrderStatus.values.byName(m['status'] as String),
          )
          ..vehicle = m['vehicle'] as int?
          ..finishedTick = m['finished'] as int?
          ..error = m['error'] as String?
          ..noRoadTicks = whole(m['noRoad'] ?? 0, 0, 1 << 40)
          ..income = whole(m['income'] ?? 0, 0, 1 << 50);
    if (w.map.industry(o.supplier) == null ||
        w.map.industry(o.receiver) == null ||
        w.orders.byId(o.id) != null) {
      throw const FormatException('Bad order in Magistrali save');
    }
    // An order in work has its truck, and the truck has it.
    final truck = o.vehicle == null ? null : w.vehicles[o.vehicle];
    final working = o.status.active && o.status != MagOrderStatus.pending;
    if (working &&
            (truck == null ||
                truck.orderId != o.id ||
                o.status.onBoard &&
                    (truck.load != o.amount || truck.cargo != o.cargo)) ||
        o.status == MagOrderStatus.pending && o.vehicle != null) {
      throw const FormatException('Inconsistent order in Magistrali save');
    }
    w.orders.orders.add(o);
  }
  for (final v in w.vehicles.values) {
    final o = v.orderId == null ? null : w.orders.byId(v.orderId!);
    if (v.orderId != null &&
        (o == null || !o.status.active || o.vehicle != v.id)) {
      throw const FormatException('Truck with a missing order');
    }
  }
  // Orders never hold more than is there.
  for (final i in w.map.industries) {
    for (final c in MagCargo.values) {
      if (w.orders.reservedOut(i.id, c) > (i.stock[c] ?? 0)) {
        throw const FormatException('Orders hold more than the stock');
      }
    }
  }
  final journal = j['journal'] as Map? ?? const {};
  w.journal.seq = whole(journal['seq'] ?? 1, 1, 1 << 50);
  for (final e in (journal['sums'] as Map? ?? const {}).entries) {
    w.journal.sums[MagEntryKind.values.byName(e.key as String)] = whole(
      e.value,
      -(1 << 50),
      1 << 50,
    );
  }
  for (final raw in journal['entries'] as List? ?? const []) {
    final m = raw as Map;
    final id = whole(m['id'], 1, w.journal.seq - 1);
    w.journal.entries.add(
      MagEntry(
        id: id,
        tick: whole(m['t'], 0, 1 << 50),
        kind: MagEntryKind.values.byName(m['k'] as String),
        category: m['c'] as String,
        amount: whole(m['a'], -(1 << 50), 1 << 50),
        source: m['s'] as String?,
        sourceId: m['si'] as int?,
        cargo: m['g'] == null ? null : MagCargo.values.byName(m['g'] as String),
        units: whole(m['u'] ?? 0, 0, 1 << 40),
      ),
    );
  }
  for (final raw in j['contracts'] as List? ?? const []) {
    final m = raw as Map;
    w.contracts.add(
      MagContract(
        id: whole(m['id'], 1, 1 << 40),
        cargo: MagCargo.values.byName(m['cargo'] as String),
        to: whole(m['to'], 1, 1 << 20),
        amount: whole(m['amount'], 1, 1 << 20),
        reward: whole(m['reward'], 0, 1 << 40),
        xp: whole(m['xp'], 0, 1 << 40),
        delivered: whole(m['delivered'], 0, 1 << 20),
      ),
    );
  }
  for (final t in j['tasks'] as List? ?? const []) {
    w.tasksDone.add(whole(t, 1, MagWorldProgress.tasks.length));
  }
  w.created.addAll(cargo(j['created']));
  w.destroyed.addAll(cargo(j['destroyed']));
  w.delivered.addAll(cargo(j['delivered']));
  w.deliveries = whole(j['deliveries'] ?? 0, 0, 1 << 40);
  w.earnedTotal = whole(j['earned'] ?? 0, 0, 1 << 50);
  final months = j['months'] as List? ?? const [];
  if (months.isNotEmpty) w.months.clear();
  for (final raw in months) {
    final m = raw as Map;
    final month = MagMonth(whole(m['index'], 0, 1 << 30))
      ..deliveries = whole(m['deliveries'] ?? 0, 0, 1 << 40);
    month.income.addAll(money(m['income']));
    month.expense.addAll(money(m['expense']));
    w.months.add(month);
  }
  final cam = j['camera'] as List?;
  if (cam != null && cam.length == 3) {
    w.cameraX = real(cam[0], -1e6, 1e6).clamp(0, size.toDouble());
    w.cameraY = real(cam[1], -1e6, 1e6).clamp(0, size.toDouble());
    w.zoom = real(cam[2], -1e6, 1e6).clamp(.4, 2.5);
  }
  final settings = j['settings'] as Map? ?? const {};
  w.autoService = settings['autoService'] as bool? ?? true;
  w.sound = settings['sound'] as bool? ?? true;
  final mode = settings['dispatch'];
  if (mode is String) {
    w.dispatchMode =
        MagDispatchMode.values.asNameMap()[mode] ?? MagDispatchMode.balanced;
  }
  // The ledger must still add up, or the file was altered or broken.
  final total = w.totalCargo();
  for (final c in MagCargo.values) {
    final expect = (w.created[c] ?? 0) - (w.destroyed[c] ?? 0);
    if ((total[c] ?? 0) != expect) {
      throw const FormatException('Magistrali save does not balance');
    }
  }
  return w;
}
