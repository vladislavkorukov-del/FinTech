part of 'world.dart';

/// Versioned JSON of a company. The map comes back from its seed; roads,
/// stocks, trucks and money are checked on load, and the cargo ledger
/// must still add up, so a broken file is refused whole.
extension MagWorldSave on MagWorld {
  /// 1: 1.68.0. 2: logistics orders (trucks may carry an order, a truck
  /// may stand idle on the map).
  static const version = 2;

  Map<String, Object?> toJson() => {
    'version': version,
    'seed': seed,
    'size': size,
    'tick': tick,
    'money': money,
    'xp': xp,
    'nextId': nextId,
    'speed': speed,
    'rng': rng,
    'roadVersion': roadVersion,
    'roads': base64Encode(roads),
    'industries': [
      for (final i in map.industries)
        {
          'id': i.id,
          if (i.stock.isNotEmpty) 'stock': _cargo(i.stock),
          if (i.input.isNotEmpty) 'input': _cargo(i.input),
        },
    ],
    'vehicles': [
      for (final v in vehicles.values)
        {
          'id': v.id,
          'model': v.model,
          'name': v.name,
          'upgrades': v.upgrades,
          'wear': v.wear,
          'odometer': v.odometer,
          'income': v.income,
          'trips': v.trips,
          'upgradeSpent': v.upgradeSpent,
          'route': v.routeId,
          if (v.orderId != null) 'order': v.orderId,
          'stop': v.stop,
          'state': v.state.name,
          if (v.load > 0) ...{
            'cargo': v.cargo!.name,
            'load': v.load,
            'loadFrom': v.loadFrom,
          },
          'cell': v.cell,
          'path': v.path,
          'pathIndex': v.pathIndex,
          'progress': v.progress,
          'dir': v.dir,
          'wait': v.wait,
          'unpaid': v.unpaid,
        },
    ],
    'routes': [
      for (final r in routes.values)
        {
          'id': r.id,
          'name': r.name,
          'stops': r.stops,
          'income': r.income,
          'deliveries': r.deliveries,
        },
    ],
    'orders': [
      for (final o in orders.orders)
        {
          'id': o.id,
          'cargo': o.cargo.name,
          'amount': o.amount,
          'from': o.supplier,
          'to': o.receiver,
          'priority': o.priority,
          'created': o.createdTick,
          if (o.tag != null) 'tag': o.tag,
          'status': o.status.name,
          if (o.vehicle != null) 'vehicle': o.vehicle,
          if (o.finishedTick != null) 'finished': o.finishedTick,
          if (o.error != null) 'error': o.error,
          if (o.noRoadTicks != 0) 'noRoad': o.noRoadTicks,
          if (o.income != 0) 'income': o.income,
        },
    ],
    'contracts': [
      for (final c in contracts)
        {
          'id': c.id,
          'cargo': c.cargo.name,
          'to': c.to,
          'amount': c.amount,
          'reward': c.reward,
          'xp': c.xp,
          'delivered': c.delivered,
        },
    ],
    'tasks': tasksDone.toList()..sort(),
    'created': _cargo(created),
    'destroyed': _cargo(destroyed),
    'delivered': _cargo(delivered),
    'deliveries': deliveries,
    'earned': earnedTotal,
    'months': [
      for (final m in months)
        {
          'index': m.index,
          'income': m.income,
          'expense': m.expense,
          'deliveries': m.deliveries,
        },
    ],
    'camera': [cameraX, cameraY, zoom],
    'settings': {'autoService': autoService, 'sound': sound},
  };

  static Map<String, int> _cargo(Map<MagCargo, int> m) => {
    for (final e in m.entries)
      if (e.value != 0) e.key.name: e.value,
  };
}

/// Reads a saved company, or throws [FormatException].
/// Brings an older save up to the current format, or throws
/// [FormatException] for a version this build does not know. New fields
/// get safe defaults: no orders, every truck stays on its own route.
Map<String, dynamic> migrateMagSave(Map<String, dynamic> j) {
  final v = j['version'];
  if (v == MagWorldSave.version) return j;
  if (v == 1) return {...j, 'version': 2, 'orders': const <Object>[]};
  throw const FormatException('Unsupported Magistrali save version');
}

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
  final w = MagWorld(map: MagMap.generate(seed, size: size));
  w.tick = whole(j['tick'], 0, 1 << 50);
  w.money = whole(j['money'], -(1 << 50), 1 << 50);
  w.xp = whole(j['xp'], 0, 1 << 50);
  w.nextId = whole(j['nextId'], 1, 1 << 40);
  w.speed = const [0, 1, 2, 4].contains(j['speed']) ? j['speed'] as int : 1;
  w.rng = whole(j['rng'] ?? 1, 0, 0x7fffffff);
  w.roadVersion = whole(j['roadVersion'] ?? 0, 0, 1 << 40);
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
