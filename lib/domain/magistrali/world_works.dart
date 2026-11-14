part of 'world.dart';

/// Rich deposits (MAP-10), what a plant processes first (BIZ-06), depots
/// (VEH-10) and merged logistics orders (LOG-15) — stage S16.
extension MagWorldWorks on MagWorld {
  // ---- MAP-10 ----

  /// A raw producer on a rich deposit: it yields half as much again. Which
  /// ones follows from the map's seed, so every save of a map agrees.
  bool isRich(MagIndustry i) {
    if (i.town != null || i.spec.produces.isEmpty || i.spec.stores) {
      return false;
    }
    var h = map.seed * 2654435761 + i.id * 40503;
    h = (h ^ (h >> 15)) & 0x7fffffff;
    return h % MagRules.richOneIn == 0;
  }

  double richFactor(MagIndustry i) =>
      (isRich(i) ? MagRules.richYield : 1) *
      mountainFactor(i) * // MAP-07
      regionFactor(i); // BIZ-12

  // ---- BIZ-06 ----

  /// The input an own plant with several recipes processes first.
  String? setFirstInput(int id, MagCargo? c) {
    final i = map.industry(id);
    if (i == null || !i.owned) return 'Настраивать можно только своё';
    if (c != null && !i.spec.converts.containsKey(c)) {
      return 'Этого предприятие не перерабатывает';
    }
    if (c == null) {
      firstInput.remove(id);
    } else {
      firstInput[id] = c;
    }
    return null;
  }

  /// The recipes of [i] in the order they are worked.
  List<MapEntry<MagCargo, MagCargo>> _recipesOf(MagIndustry i) {
    final list = i.spec.converts.entries.toList();
    final first = firstInput[i.id];
    if (first != null && i.owned) {
      list.sort((a, b) => (a.key == first ? 0 : 1) - (b.key == first ? 0 : 1));
    }
    return list;
  }

  // ---- VEH-10 ----

  int get depotSlots => 1 + level ~/ 8;

  String? depotBlocker(int cell) {
    if (roads[cell] == 0) return 'Депо ставится на дорогу';
    if (depots.contains(cell)) return 'Здесь уже депо';
    if (depots.length >= depotSlots) {
      return 'Больше депо пока нельзя (${depots.length} из $depotSlots)';
    }
    return null;
  }

  String? buildDepot(int cell) {
    final why = depotBlocker(cell);
    if (why != null) return why;
    if (money < MagRules.depotPrice) return 'Не хватает кредитов';
    _spend(MagRules.depotPrice, 'depots');
    depots.add(cell);
    _say('Депо построено');
    _remember('Построено депо');
    return null;
  }

  String? removeDepot(int cell) {
    if (!depots.remove(cell)) return 'Здесь нет депо';
    _assetSale(
      (MagRules.depotPrice * MagRules.demolishRefund).round(),
      'depot_sale',
    );
    return null;
  }

  /// A vehicle drives through a depot: worn ones are repaired there,
  /// cheaper than on the road (VEH-10).
  void _atDepot(MagVehicle v, int cell) {
    if (!depots.contains(cell) || v.wear < MagRules.depotWear) return;
    final cost = (serviceCost(v) * MagRules.depotService).round();
    if (cost <= 0 || money < cost) return;
    _spend(cost, 'service', source: 'vehicle', sourceId: v.id);
    v
      ..wear = 0
      ..costs += cost;
    routes[v.routeId]?.costs += cost;
  }

  /// Each depot lowers the upkeep of the whole fleet a little.
  double get depotUpkeep =>
      1 - math.min(3, depots.length) * MagRules.depotUpkeepCut;

  // ---- LOG-15 ----

  /// Joins waiting orders with the same cargo, supplier and receiver into
  /// one (no bigger than the biggest vehicle carries); returns how many
  /// were joined.
  int mergeOrders() {
    final cap = vehicles.values.isEmpty
        ? 0
        : vehicles.values.map(capacityOf).reduce(math.max);
    var n = 0;
    final waiting = [
      for (final o in orders.active)
        if (o.status == MagOrderStatus.pending && o.vehicle == null) o,
    ];
    for (var a = 0; a < waiting.length; a++) {
      final x = waiting[a];
      if (!x.status.active) continue;
      for (var b = a + 1; b < waiting.length; b++) {
        final y = waiting[b];
        if (!y.status.active ||
            y.cargo != x.cargo ||
            y.supplier != x.supplier ||
            y.receiver != x.receiver ||
            x.amount + y.amount > cap) {
          continue;
        }
        x.amount += y.amount;
        _closeOrder(
          y,
          MagOrderStatus.cancelled,
          'Объединён с заказом #${x.id}',
        );
        n++;
      }
    }
    return n;
  }

  // ---- Saves ----

  Map<String, Object> _saveWorks() => {
    if (deals.isNotEmpty) 'deals': [for (final d in deals) d.toJson()],
    if (firstInput.isNotEmpty)
      'firstInput': {
        for (final e in firstInput.entries) '${e.key}': e.value.name,
      },
    if (depots.isNotEmpty) 'depots': depots.toList()..sort(),
    if (!autoMerge) 'autoMerge': false,
  };

  void loadWorks(Map<String, dynamic> j) {
    for (final raw in j['deals'] as List? ?? const []) {
      deals.add(MagDeal.fromJson(raw as Map));
    }
    for (final e in (j['firstInput'] as Map? ?? const {}).entries) {
      firstInput[int.parse('${e.key}')] = MagCargo.values.byName(
        e.value as String,
      );
    }
    for (final c in j['depots'] as List? ?? const []) {
      if (c is! int || c < 0 || c >= size * size || roads[c] == 0) {
        throw const FormatException('Bad depot in Magistrali save');
      }
      depots.add(c);
    }
    autoMerge = j['autoMerge'] as bool? ?? true;
  }
}
