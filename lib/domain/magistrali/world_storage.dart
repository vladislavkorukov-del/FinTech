part of 'world.dart';

/// Smart warehouses: a building that stores any cargo and, by its rules,
/// writes logistics orders itself — refilling what runs low, sending on
/// what is above the target. Orders already on their way count, and each
/// rule has only a few orders open at once, so requests never pile up.
extension MagWorldStorage on MagWorld {
  Iterable<MagIndustry> get warehouses =>
      map.industries.where((i) => i.spec.stores);

  /// How many warehouses the company may have (technologies).
  int get warehouseSlots => bonus(MagBonus.warehouses).round();

  /// Room in each warehouse, all cargo together.
  int get warehouseCapacity =>
      MagRules.warehouseBase + bonus(MagBonus.storage).round();

  /// Room of one warehouse: the base room, more with each level.
  int warehouseCapacityOf(MagIndustry w) =>
      (warehouseCapacity * storageFactor(w)).round();

  /// Price of the next warehouse level (null at the top level).
  int? warehouseUpgradePrice(MagIndustry w) =>
      w.level >= MagRules.maxIndustryLevel
      ? null
      : (MagRules.warehousePrice * .5 * w.level).round();

  /// A bigger warehouse: +50% room per level, up to level 5.
  String? upgradeWarehouse(int id) {
    final w = map.industry(id);
    if (w == null || !w.spec.stores) return 'Это не склад';
    final cost = warehouseUpgradePrice(w);
    if (cost == null) return 'Максимальный уровень';
    if (money < cost) return 'Не хватает кредитов: нужно $cost';
    _spend(cost, 'warehouse_upgrade', source: 'industry', sourceId: id);
    w
      ..level += 1
      ..invested += cost;
    _say('${w.name}: уровень ${w.level}, место ${warehouseCapacityOf(w)}');
    return null;
  }

  int get warehousePrice =>
      (MagRules.warehousePrice * (1 + .5 * warehouses.length)).round();

  bool modeUnlocked(MagStockMode m) => switch (m) {
    MagStockMode.manual => true,
    MagStockMode.autoSupply => bonus(MagBonus.autoSupply) > 0,
    MagStockMode.distribute => bonus(MagBonus.distribute) > 0,
  };

  int storedIn(MagIndustry w) => w.stock.values.fold(0, (a, b) => a + b);

  MagStockRule ruleOf(MagIndustry w, MagCargo c) =>
      w.rules[c] ?? MagStockRule();

  /// Room for [c] in a warehouse: its own limit and the shared space, both
  /// minus what is already on its way here.
  int _warehouseRoom(MagIndustry w, MagCargo c) {
    var inbound = 0;
    for (final k in MagCargo.values) {
      inbound += orders.reservedIn(w.id, k);
    }
    final shared = warehouseCapacityOf(w) - storedIn(w) - inbound;
    final rule = ruleOf(w, c);
    final own =
        (rule.max ?? warehouseCapacityOf(w)) -
        (w.stock[c] ?? 0) -
        orders.reservedIn(w.id, c);
    return math.max(0, math.min(shared, own));
  }

  /// Why a warehouse cannot stand with its corner at (x, y).
  String? warehouseBlocker(int x, int y) {
    if (warehouseSlots == 0) return 'Нужна технология «Складское дело»';
    if (warehouses.length >= warehouseSlots) {
      return 'Больше складов откроют технологии ветки «Склады»';
    }
    const s = 2;
    for (var yy = y; yy < y + s; yy++) {
      for (var xx = x; xx < x + s; xx++) {
        if (!map.roadable(xx, yy) || hasRoad(xx, yy)) {
          return 'Нужны 2×2 свободные клетки без дорог';
        }
      }
    }
    return null;
  }

  String? buildWarehouse(int x, int y) {
    final why = warehouseBlocker(x, y);
    if (why != null) return why;
    final price = warehousePrice;
    if (money < price) return 'Не хватает кредитов: нужно $price';
    _spend(price, 'warehouses');
    final n = warehouses.length + 1;
    map.industries.add(
      MagIndustry(
        id: MagRules.warehouseIdBase + nextId++,
        kind: MagIndustryKind.warehouse,
        x: x,
        y: y,
        name: 'Склад №$n',
      )..since = tick,
    );
    roadVersion++; // a new place: stop cells may change
    _say('Склад построен — подведите к нему дорогу');
    return null;
  }

  /// Takes an empty warehouse down (half its price back).
  String? removeWarehouse(int id) {
    final w = map.industry(id);
    if (w == null || !w.spec.stores) return 'Это не склад';
    if (storedIn(w) > 0) return 'Сначала вывезите груз';
    if (orders.active.any((o) => o.supplier == id || o.receiver == id)) {
      return 'К складу привязаны заказы';
    }
    if (routes.values.any((r) => r.stops.contains(id))) {
      return 'Склад есть в маршруте';
    }
    map.industries.remove(w);
    final back = ((MagRules.warehousePrice + w.invested) * .5).round();
    _assetSale(back, 'warehouse_sale', source: 'industry', sourceId: id);
    roadVersion++;
    return null;
  }

  /// Changes how a warehouse keeps [c].
  String? setRule(int id, MagCargo c, MagStockRule rule) {
    final w = map.industry(id);
    if (w == null || !w.spec.stores) return 'Это не склад';
    if (!modeUnlocked(rule.mode)) return 'Режим откроет технология';
    final cap = warehouseCapacityOf(w);
    final max = rule.max ?? cap;
    if (rule.min < 0 ||
        rule.min > rule.target ||
        rule.target > max ||
        max > cap) {
      return 'Нужно: минимум ≤ желаемый ≤ максимум ≤ $cap';
    }
    if (rule.priority < 0 || rule.priority > 2) return 'Нет такого приоритета';
    w.rules[c] = rule;
    return null;
  }

  /// Largest load one order may carry (the biggest truck the company has).
  int get _batch => math.max(
    MagRules.truck('cart')!.capacity,
    vehicles.values.fold(0, (m, v) => math.max(m, capacityOf(v))),
  );

  /// Stock a warehouse will have once its orders arrive and leave.
  int projectedStock(MagIndustry w, MagCargo c) =>
      (w.stock[c] ?? 0) +
      orders.reservedIn(w.id, c) -
      orders.reservedOut(w.id, c);

  /// The planning pass: every warehouse rule writes the orders it needs.
  void _planLogistics() {
    for (final w in warehouses.toList()) {
      for (final e in w.rules.entries.toList()) {
        switch (e.value.mode) {
          case MagStockMode.manual:
            break;
          case MagStockMode.autoSupply:
            if (modeUnlocked(MagStockMode.autoSupply)) {
              _refill(w, e.key, e.value);
            }
          case MagStockMode.distribute:
            if (modeUnlocked(MagStockMode.distribute)) {
              _sendOn(w, e.key, e.value);
            }
        }
      }
    }
  }

  String _tagOf(MagIndustry w, MagCargo c) => 'wh:${w.id}:${c.name}';

  int _openOrders(String tag) =>
      orders.active.where((o) => o.tag == tag).length;

  /// Below the minimum (counting what is on its way): order up to the
  /// target from the nearest suppliers joined by road.
  void _refill(MagIndustry w, MagCargo c, MagStockRule r) {
    final tag = _tagOf(w, c);
    var need = r.target - projectedStock(w, c);
    if (projectedStock(w, c) >= r.min || need <= 0) return;
    final sources = map.industries.where((i) {
      if (i.id == w.id || !i.supplies.contains(c)) return false;
      if (i.spec.stores) {
        // Another warehouse gives only what it sends on, above its target.
        final ir = ruleOf(i, c);
        return ir.mode == MagStockMode.distribute && _surplus(i, c, ir) > 0;
      }
      return availableOf(i, c) > 0;
    }).toList()..sort((a, b) => a.distanceTo(w).compareTo(b.distanceTo(w)));
    for (final s in sources) {
      if (need <= 0 || _openOrders(tag) >= MagRules.autoOrdersPerRule) return;
      if (!connected(s, w)) continue;
      final free = s.spec.stores
          ? _surplus(s, c, ruleOf(s, c))
          : availableOf(s, c);
      final amount = [
        need,
        free,
        _batch,
        _warehouseRoom(w, c),
      ].reduce(math.min);
      if (amount <= 0) continue;
      if (createOrder(
            cargo: c,
            from: s.id,
            to: w.id,
            amount: amount,
            priority: r.priority,
            tag: tag,
          ) ==
          null) {
        need -= amount;
      }
    }
  }

  /// What a distributing warehouse may send away: above its target.
  int _surplus(MagIndustry w, MagCargo c, MagStockRule r) =>
      availableOf(w, c) - r.target;

  /// Above the target: send the extra to the nearest places that use it
  /// (plants and towns, never other warehouses — those pull for
  /// themselves, so cargo never goes round in circles).
  void _sendOn(MagIndustry w, MagCargo c, MagStockRule r) {
    final tag = _tagOf(w, c);
    var extra = _surplus(w, c, r);
    if (extra < MagRules.minAutoBatch) return;
    final sinks =
        map.industries
            .where((i) => !i.spec.stores && i.accepts.contains(c))
            .toList()
          ..sort((a, b) => a.distanceTo(w).compareTo(b.distanceTo(w)));
    for (final s in sinks) {
      if (extra < MagRules.minAutoBatch ||
          _openOrders(tag) >= MagRules.autoOrdersPerRule) {
        return;
      }
      if (!connected(w, s)) continue;
      final amount = [extra, roomOf(s, c) ?? 0, _batch].reduce(math.min);
      if (amount <= 0) continue;
      if (createOrder(
            cargo: c,
            from: w.id,
            to: s.id,
            amount: amount,
            priority: r.priority,
            tag: tag,
          ) ==
          null) {
        extra -= amount;
      }
    }
  }

  /// Gives free trucks to waiting orders, most urgent first (a one-off
  /// action of the player; the automatic dispatcher is the next stage).
  int assignFreeTrucks() {
    var n = 0;
    final waiting =
        orders.active.where((o) => o.status == MagOrderStatus.pending).toList()
          ..sort((a, b) {
            final p = b.priority.compareTo(a.priority);
            return p != 0 ? p : a.createdTick.compareTo(b.createdTick);
          });
    for (final o in waiting) {
      final free = vehicles.values
          .where((v) => isFree(v) && capacityOf(v) >= o.amount)
          .toList();
      if (free.isEmpty) continue;
      final from = map.industry(o.supplier)!;
      // The nearest free truck (in the garage counts as at the supplier).
      double dist(MagVehicle v) => v.onMap
          ? ((cx(v.cell) - from.centerX).abs() +
                (cy(v.cell) - from.centerY).abs())
          : 0;
      free.sort((a, b) => dist(a).compareTo(dist(b)));
      if (assignOrder(o.id, free.first.id) == null) n++;
    }
    return n;
  }
}
