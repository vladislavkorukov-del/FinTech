part of 'world.dart';

/// Settlements living on their own. Each day a settlement uses up what its
/// level needs (regular supply), remembers how well it was supplied, gains
/// or slowly loses people, and grows a level when it has enough people and
/// got the one-off delivery its growth asks for. Growing takes real land
/// next to it — never roads, places or the player's buildings — and a
/// settlement never drops a level it has reached.
extension MagWorldSettlements on MagWorld {
  Iterable<MagIndustry> get settlements =>
      map.industries.where((i) => i.town != null);

  /// Can the world make [c] at all now (a producer, or a plant whose input
  /// can be made)? Needs and growth never ask for cargo nobody can make.
  bool cargoAvailable(MagCargo c) {
    final made = <MagCargo>{};
    for (final i in map.industries) {
      if (i.town == null && !i.spec.stores) made.addAll(i.spec.produces.keys);
    }
    var more = true;
    while (more) {
      more = false;
      for (final i in map.industries) {
        for (final e in i.spec.converts.entries) {
          if (made.contains(e.key) && made.add(e.value)) more = true;
        }
      }
    }
    return made.contains(c);
  }

  /// Regular needs today that the world can meet.
  Map<MagCargo, int> needsOf(MagIndustry i) => {
    for (final e in i.town!.spec.needs.entries)
      if (cargoAvailable(e.key)) e.key: e.value,
  };

  /// What growth to the next level still asks for (only cargo the world
  /// can make; empty when nothing is missing).
  Map<MagCargo, int> missingForGrowth(MagIndustry i) {
    final t = i.town!;
    return {
      for (final e in t.spec.development.entries)
        if (cargoAvailable(e.key) && (t.devStock[e.key] ?? 0) < e.value)
          e.key: e.value - (t.devStock[e.key] ?? 0),
    };
  }

  /// What the development contract of this level asks for (only cargo the
  /// world can make).
  Map<MagCargo, int> developmentAsks(MagIndustry i) => {
    for (final e in i.town!.spec.development.entries)
      if (cargoAvailable(e.key)) e.key: e.value,
  };

  /// Reward of the current development contract (0 at the top level).
  int developmentReward(MagIndustry i) {
    final asks = developmentAsks(i);
    return asks.isEmpty ? 0 : MagTowns.devReward(i.town!.level, asks);
  }

  /// Pays the development contract once, when everything it asks for has
  /// been delivered.
  void _payDevelopment(MagIndustry i) {
    final t = i.town!;
    if (t.devPaid || t.level >= MagTowns.maxLevel) return;
    if (developmentAsks(i).isEmpty || missingForGrowth(i).isNotEmpty) return;
    final reward = developmentReward(i);
    t
      ..devPaid = true
      ..reputation += 50;
    _earn(reward, 'development', source: 'settlement', sourceId: i.id);
    _gainXp(math.max(1, reward ~/ 10));
    t.remember(tick, 'Контракт развития выполнен: +$reward кр');
    _say('${i.name}: контракт развития выполнен, +$reward кр');
  }

  /// Delivered cargo arrives in a settlement: first its pantry for regular
  /// needs (a few days' worth), then what growth asks for (kept until
  /// growth), the rest is sold in its market (used up). Each unit goes to
  /// exactly one of these.
  void _townReceive(MagIndustry i, MagCargo c, int n) {
    final t = i.town!;
    final need = needsOf(i)[c] ?? 0;
    final room = need * MagTowns.pantryDays - (t.pantry[c] ?? 0);
    final regular = math.max(0, math.min(n, room));
    if (regular > 0) t.pantry[c] = (t.pantry[c] ?? 0) + regular;
    var rest = n - regular;
    final want = t.spec.development[c];
    if (want != null && cargoAvailable(c)) {
      final dev = math.min(rest, math.max(0, want - (t.devStock[c] ?? 0)));
      if (dev > 0) t.devStock[c] = (t.devStock[c] ?? 0) + dev;
      rest -= dev;
    }
    destroyed[c] = (destroyed[c] ?? 0) + rest; // sold in its market
    _payDevelopment(i);
    if (t.reputation == 0) {
      t.remember(tick, 'Первая поставка от вашей компании');
    }
    t.reputation += n;
  }

  /// The daily life of every settlement.
  void _dayTowns() {
    for (final i in settlements.toList()) {
      final t = i.town!;
      // Growth stock beyond what this level asks for goes to the market.
      final asks = developmentAsks(i);
      for (final c in t.devStock.keys.toList()) {
        final extra = t.devStock[c]! - (asks[c] ?? 0);
        if (extra > 0) {
          t.devStock[c] = t.devStock[c]! - extra;
          if (t.devStock[c] == 0) t.devStock.remove(c);
          destroyed[c] = (destroyed[c] ?? 0) + extra;
        }
      }
      _payDevelopment(i);
      final needs = needsOf(i);
      var met = 1.0;
      if (needs.isNotEmpty) {
        met = 0;
        for (final e in needs.entries) {
          // The day's need is eaten from the pantry.
          final use = math.min(e.value, t.pantry[e.key] ?? 0);
          if (use > 0) {
            t.pantry[e.key] = t.pantry[e.key]! - use;
            if (t.pantry[e.key] == 0) t.pantry.remove(e.key);
            destroyed[e.key] = (destroyed[e.key] ?? 0) + use;
          }
          met += use / e.value;
        }
        met /= needs.length;
      }
      t.satisfaction.add(met);
      if (t.satisfaction.length > MagTowns.memoryDays) {
        t.satisfaction.removeAt(0);
      }
      final avg = t.averageSatisfaction;
      final floor = t.spec.population;
      final cap = t.level < MagTowns.maxLevel
          ? MagTowns.of(t.level + 1).population
          : (floor * 1.5).round();
      if (avg >= MagTowns.growAt) {
        final gain = math.max(
          1,
          (t.population * MagTowns.growth * avg).round(),
        );
        t.population = math.min(cap, t.population + gain);
      } else if (avg < MagTowns.shrinkAt) {
        final loss = (t.population * MagTowns.decline).round();
        t.population = math.max(floor, t.population - loss);
      }
      if (t.level < MagTowns.maxLevel &&
          t.population >= cap &&
          missingForGrowth(i).isEmpty) {
        _growTown(i);
      }
    }
  }

  /// Can a settlement take this cell when it grows?
  bool _townLandFree(MagIndustry i, int x, int y) {
    if (x < 1 || y < 1 || x >= size - 1 || y >= size - 1) return false;
    final k = map.at(x, y);
    if (k == MagTerrain.lake || k == MagTerrain.river) return false;
    if (hasRoad(x, y)) return false;
    final other = map.industryAt(x, y);
    return other == null || other == i;
  }

  /// Grows a settlement one level onto new land next to it.
  bool _growTown(MagIndustry i) {
    final t = i.town!;
    final next = MagTowns.of(t.level + 1);
    final land = Set<int>.of(t.cells);
    if (!MagMap.expandCells(
      land,
      next.cells,
      (x, y) => _townLandFree(i, x, y),
    )) {
      if (t.blocked == null) {
        t.remember(tick, 'Рост остановлен: вокруг нет свободной земли');
      }
      t.blocked = 'Нет свободной земли: мешают дороги, вода или постройки';
      return false;
    }
    // The growth delivery is used up once.
    for (final e in t.spec.development.entries) {
      if (!cargoAvailable(e.key)) continue;
      t.devStock[e.key] = (t.devStock[e.key] ?? 0) - e.value;
      destroyed[e.key] = (destroyed[e.key] ?? 0) + e.value;
      if (t.devStock[e.key] == 0) t.devStock.remove(e.key);
    }
    t.cells
      ..clear()
      ..addAll(land);
    t.level++;
    t
      ..blocked = null
      ..devPaid = false;
    t.remember(tick, 'Вырос до уровня ${t.level}: ${next.name}');
    roadVersion++; // its stop cells changed
    _say('${i.name} вырос: ${next.name}');
    return true;
  }
}
