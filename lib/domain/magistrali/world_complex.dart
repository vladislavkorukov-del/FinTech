part of 'world.dart';

/// Special bodies and comfort (VEH-05, PASS-07), waiting passengers,
/// industrial complexes (BIZ-14), city terminals (CITY-13), ship hulls
/// (SEA-05) and start scenarios (META-11) — stage S17.
enum MagScenario { classic, rich, railway, river, industrial, sandbox }

extension MagWorldComplex on MagWorld {
  // ---- VEH-05 / PASS-07: what a vehicle may carry and how it pays ----

  /// Fresh food a refrigerated body keeps (paid more).
  static const fresh = {MagCargo.food, MagCargo.bread, MagCargo.flour};

  /// Bulk a dump body carries.
  static const bulk = {
    MagCargo.ore,
    MagCargo.coal,
    MagCargo.stone,
    MagCargo.clay,
    MagCargo.grain,
  };

  /// What a body allows (null: no special body — then the general rule).
  bool? _bodyAllows(MagVehicle v, MagCargo c) {
    if (c.liquid) {
      return v.spec.rail || v.spec.water || v.spec.body == 'tank';
    }
    return switch (v.spec.body) {
      'tank' => false,
      'reefer' => fresh.contains(c),
      'dump' => bulk.contains(c),
      _ => null,
    };
  }

  /// Pay factor of a delivery for the vehicle's body and comfort:
  /// refrigerated fresh food +15%, people by their comfort.
  double cargoPayFactor(MagVehicle v, MagCargo c) {
    if (c.people) return v.spec.comfort;
    if (v.spec.body == 'reefer' && fresh.contains(c)) {
      return MagRules.reeferBonus;
    }
    if (v.spec.body == 'retro') return MagRules.veteranBonus; // VEH-14
    return 1;
  }

  // ---- PASS-07: people tired of waiting go home ----

  void _peopleLeave(MagIndustry i) {
    final n = ((i.stock[MagCargo.passengers] ?? 0) * MagRules.waitLeave)
        .floor();
    if (n <= 0) return;
    i.stock[MagCargo.passengers] = i.stock[MagCargo.passengers]! - n;
    destroyed[MagCargo.passengers] = (destroyed[MagCargo.passengers] ?? 0) + n;
  }

  // ---- BIZ-14: industrial complexes ----

  /// An own plant close by (5 cells) that takes what [i] makes, or makes
  /// what it takes: together they are a complex.
  MagIndustry? complexPartner(MagIndustry i) {
    if (!i.owned || i.town != null || i.spec.stores) return null;
    final out = {...i.spec.produces.keys, ...i.spec.converts.values};
    for (final o in map.industries) {
      if (o == i || !o.owned || o.town != null) continue;
      if (o.distanceTo(i) > MagRules.complexReach) continue;
      final oOut = {...o.spec.produces.keys, ...o.spec.converts.values};
      if (out.any(o.spec.takesIn) || oOut.any(i.spec.takesIn)) return o;
    }
    return null;
  }

  double complexBonusOf(MagIndustry i) =>
      complexPartner(i) == null ? 0 : MagRules.complexBonus;

  /// The conveyor of a complex: up to 20 units a day go straight from the
  /// plant that makes them to the one that uses them (a transfer).
  void _dayComplexes() {
    for (final a in map.industries) {
      final b = complexPartner(a);
      if (b == null) continue;
      for (final c in {...a.spec.produces.keys, ...a.spec.converts.values}) {
        if (!b.spec.takesIn(c)) continue;
        final n = math.min(MagRules.conveyorPerDay, availableOf(a, c));
        if (n <= 0) continue;
        a.stock[c] = a.stock[c]! - n;
        b.input[c] = (b.input[c] ?? 0) + n;
      }
    }
  }

  // ---- CITY-13: terminals at a settlement ----

  /// How many terminals a settlement may have.
  int terminalSlots(MagIndustry t) => 1 + t.town!.level ~/ 3;

  int terminalsOf(MagIndustry t) =>
      terminals.values.where((id) => id == t.id).length;

  /// Settlements whose edge [cell] touches.
  List<MagIndustry> townsBeside(int cell) => [
    for (final i in settlements)
      if (_touches(cell, i)) i,
  ];

  String? terminalBlocker(int cell, int townId) {
    final t = map.industry(townId);
    if (t == null || t.town == null) return 'Нет такого поселения';
    if (roads[cell] == 0) return 'Терминал ставится на дорогу';
    if (terminals.containsKey(cell)) return 'Здесь уже терминал';
    if (!_touches(cell, t)) return 'Терминал — у края поселения';
    if (terminalsOf(t) >= terminalSlots(t)) {
      return 'У «${t.name}» больше терминалов не поместится';
    }
    return null;
  }

  String? buildTerminal(int cell, int townId) {
    final why = terminalBlocker(cell, townId);
    if (why != null) return why;
    if (money < MagRules.terminalPrice) return 'Не хватает кредитов';
    _spend(MagRules.terminalPrice, 'terminals');
    terminals[cell] = townId;
    _remember('Терминал у «${map.industry(townId)!.name}»');
    return null;
  }

  String? removeTerminal(int cell) {
    if (terminals.remove(cell) == null) return 'Здесь нет терминала';
    _assetSale(
      (MagRules.terminalPrice * MagRules.demolishRefund).round(),
      'terminal_sale',
    );
    return null;
  }

  /// A settlement's market pays more with each terminal (up to three).
  double terminalBonusOf(MagIndustry t) =>
      math.min(3, terminalsOf(t)) * MagRules.terminalBonus;

  // ---- SEA-05: ship hulls ----

  int? hullPrice(MagVehicle v) => !v.spec.water || v.hull >= MagRules.maxHull
      ? null
      : (v.spec.price * .35 * (v.hull + 1)).round();

  String? upgradeHull(int id) {
    final v = vehicles[id];
    if (v == null) return 'Нет такого судна';
    final cost = hullPrice(v);
    if (cost == null) return v.spec.water ? 'Корпус уже лучший' : 'Только суда';
    if (money < cost) return 'Не хватает кредитов';
    _spend(cost, 'upgrades', source: 'vehicle', sourceId: id);
    v
      ..hull += 1
      ..upgradeSpent += cost;
    return null;
  }

  // ---- META-11: start scenarios ----

  void _applyScenario(MagScenario s) {
    scenario = s;
    switch (s) {
      case MagScenario.classic:
        break;
      case MagScenario.rich:
        money = 30000;
      case MagScenario.railway:
        xp = MagWorldProgress.xpFor(6);
        techs.addAll(['stud', 'steam', 'milling']);
        money = 25000;
      case MagScenario.river:
        xp = MagWorldProgress.xpFor(8);
        techs.addAll(['stud', 'shipping', 'milling']);
        money = 25000;
      case MagScenario.sandbox:
        // MAP-12: everything open, money without end, no rewards.
        money = 10000000;
        xp = MagWorldProgress.xpFor(30);
        techs.addAll(MagTechTree.all.map((t) => t.id));
      case MagScenario.industrial:
        final p = map.startPlant;
        p
          ..owned = true
          ..since = tick
          ..invested = p.spec.price;
        techs.addAll(['milling', 'carpentry']);
        money = 5000;
    }
    _remember('Начало: ${scenarioTitle(s)}');
  }

  static String scenarioTitle(MagScenario s) => switch (s) {
    MagScenario.classic => 'классический старт',
    MagScenario.rich => 'богатый наследник',
    MagScenario.railway => 'железнодорожник',
    MagScenario.river => 'речник',
    MagScenario.industrial => 'промышленник',
    MagScenario.sandbox => 'песочница',
  };

  // ---- Saves ----

  Map<String, Object> _saveComplex() => {
    if (terminals.isNotEmpty)
      'terminals': {for (final e in terminals.entries) '${e.key}': e.value},
    if (vehicles.values.any((v) => v.hull > 0))
      'hulls': {
        for (final v in vehicles.values)
          if (v.hull > 0) '${v.id}': v.hull,
      },
    if (scenario != MagScenario.classic) 'scenario': scenario.name,
  };

  void loadComplex(Map<String, dynamic> j) {
    for (final e in (j['terminals'] as Map? ?? const {}).entries) {
      final cell = int.parse('${e.key}');
      final t = map.industry(e.value as int);
      if (t?.town == null || cell < 0 || cell >= size * size) {
        throw const FormatException('Bad terminal in Magistrali save');
      }
      terminals[cell] = t!.id;
    }
    final s = j['scenario'];
    if (s is String) scenario = MagScenario.values.byName(s);
  }

  /// Vessel hulls, read once the vehicles are there.
  void loadHulls(Map<String, dynamic> j) {
    loadNetwork(j); // paints too need the vehicles
    loadRivals(j); // the collection of an old save comes from its fleet
    loadFinish(j);
    loadBiomes(j);
    loadSeasons(j);
    for (final e in (j['hulls'] as Map? ?? const {}).entries) {
      final v = vehicles[int.parse('${e.key}')];
      final n = e.value;
      if (v == null || n is! int || n < 0 || n > MagRules.maxHull) {
        throw const FormatException('Bad hull in Magistrali save');
      }
      v.hull = n;
    }
  }
}
