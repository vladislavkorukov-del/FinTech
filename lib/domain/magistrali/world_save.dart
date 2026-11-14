part of 'world.dart';

/// Versioned JSON of a company. The map comes back from its seed; roads,
/// stocks, trucks and money are checked on load, and the cargo ledger
/// must still add up, so a broken file is refused whole.
extension MagWorldSave on MagWorld {
  /// 1: 1.68.0. 2: logistics orders (trucks may carry an order, a truck
  /// may stand idle on the map).
  /// 3: technologies and warehouses with their rules.
  /// 4: the automatic fleet (a flag per truck) and the dispatcher mode.
  /// 5: settlements (level, people, land, supply, growth, story) and the
  /// map generator version.
  /// 6: own businesses (owned, level, built, figures) and the journal.
  static const version = 6;

  Map<String, Object?> toJson() => {
    'version': version,
    'seed': seed,
    'size': size,
    'tick': tick,
    'mapVersion': map.version,
    'settlements': [
      for (final i in settlements)
        {
          'id': i.id,
          'level': i.town!.level,
          'population': i.town!.population,
          'specialization': i.town!.specialization.name,
          'cells': i.town!.cells.toList()..sort(),
          if (i.town!.pantry.isNotEmpty) 'pantry': _cargo(i.town!.pantry),
          'satisfaction': i.town!.satisfaction,
          if (i.town!.devStock.isNotEmpty) 'dev': _cargo(i.town!.devStock),
          'reputation': i.town!.reputation,
          if (i.town!.devPaid) 'devPaid': true,
          if (i.town!.revenue != 0) 'revenue': i.town!.revenue,
          if (i.town!.delivered != 0) 'delivered': i.town!.delivered,
          if (i.town!.received.isNotEmpty) 'received': _cargo(i.town!.received),
          if (i.town!.orderAt != 0) 'orderAt': i.town!.orderAt,
          if (i.town!.blocked != null) 'blocked': i.town!.blocked,
          'history': [
            for (final e in i.town!.history) [e.tick, e.text],
          ],
        },
    ],
    'money': money,
    'xp': xp,
    'nextId': nextId,
    'speed': speed,
    'rng': rng,
    'roadVersion': roadVersion,
    'roads': base64Encode(roads),
    if (rails.any((r) => r != 0)) 'rails': base64Encode(rails),
    if (stations.isNotEmpty)
      'stations': [
        for (final e in stations.entries) [e.key, e.value],
      ],
    if (ports.isNotEmpty)
      'ports': [
        for (final e in ports.entries) [e.key, e.value],
      ],
    'industries': [
      for (final i in map.industries)
        {
          'id': i.id,
          if (i.stock.values.any((n) => n != 0)) 'stock': _cargo(i.stock),
          if (i.input.values.any((n) => n != 0)) 'input': _cargo(i.input),
          if (i.owned) 'owned': true,
          if (i.level != 1) 'level': i.level,
          if (i.invested != 0) 'invested': i.invested,
          if (i.revenue != 0) 'revenue': i.revenue,
          if (i.costs != 0) 'costs': i.costs,
          if (i.produced != 0) 'produced': i.produced,
          if (i.sold != 0) 'sold': i.sold,
          if (i.since != null) 'since': i.since,
          if (!i.supplyPlants) 'noPlants': true,
          if (!i.supplyTowns) 'noTowns': true,
          if (i.ordersMade != 0) 'ordersMade': i.ordersMade,
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
          if (v.auto) 'auto': true,
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
          if (v.wagons != 0) 'wagons': v.wagons,
          if (v.blocked != 0) 'blocked': v.blocked,
          if (v.yields != 0) 'yields': v.yields,
          if (v.costs != 0) 'costs': v.costs,
          if (v.emptyCells != 0) 'empty': v.emptyCells,
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
          if (r.costs != 0) 'costs': r.costs,
          if (r.cells != 0) 'cells': r.cells,
          if (r.emptyCells != 0) 'empty': r.emptyCells,
        },
    ],
    'techs': techs.toList()..sort(),
    'warehouses': [
      for (final w in warehouses)
        {
          'id': w.id,
          'x': w.x,
          'y': w.y,
          'name': w.name,
          'rules': {
            for (final e in w.rules.entries)
              e.key.name: {
                'mode': e.value.mode.name,
                'min': e.value.min,
                'target': e.value.target,
                if (e.value.max != null) 'max': e.value.max,
                'priority': e.value.priority,
              },
          },
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
    'built': [
      for (final i in map.industries)
        if (i.built)
          {'id': i.id, 'kind': i.kind.name, 'x': i.x, 'y': i.y, 'name': i.name},
    ],
    'journal': {
      'seq': journal.seq,
      'sums': {for (final e in journal.sums.entries) e.key.name: e.value},
      'entries': [
        for (final e in journal.entries)
          {
            'id': e.id,
            't': e.tick,
            'k': e.kind.name,
            'c': e.category,
            'a': e.amount,
            if (e.source != null) 's': e.source,
            if (e.sourceId != null) 'si': e.sourceId,
            if (e.cargo != null) 'g': e.cargo!.name,
            if (e.units != 0) 'u': e.units,
          },
      ],
    },
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
          if (c.deadline != null) 'deadline': c.deadline,
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
    'settings': {
      'autoService': autoService,
      'sound': sound,
      'dispatch': dispatchMode.name,
    },
  };

  static Map<String, int> _cargo(Map<MagCargo, int> m) => {
    for (final e in m.entries)
      if (e.value != 0) e.key.name: e.value,
  };
}

/// Brings an older save up to the current format, or throws
/// [FormatException] for a version this build does not know. New fields
/// get safe defaults: no orders, every truck stays on its own route.
Map<String, dynamic> migrateMagSave(Map<String, dynamic> j) {
  final v = j['version'];
  if (v == MagWorldSave.version) return j;
  if (v == 1) {
    return migrateMagSave({...j, 'version': 2, 'orders': const <Object>[]});
  }
  if (v == 2) {
    return migrateMagSave({
      ...j,
      'version': 3,
      'techs': const <Object>[],
      'warehouses': const <Object>[],
    });
  }
  // Format 3 → 4: every truck stays under manual control.
  if (v == 3) return migrateMagSave({...j, 'version': 4});
  // Format 4 → 5: the old map (generator 1); its villages and cities
  // become settlements of matching level on the land they cover.
  if (v == 4) return migrateMagSave({...j, 'version': 5, 'mapVersion': 1});
  // Format 5 → 6: nothing owned, an empty journal.
  if (v == 5) return {...j, 'version': 6};
  throw const FormatException('Unsupported Magistrali save version');
}
