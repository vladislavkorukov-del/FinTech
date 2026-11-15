part of 'world.dart';

/// The land of a region (MAP-09).
enum MagBiome { meadows, steppe, taiga, highlands, lakes }

/// A city's subsidy for a line (CONT-10): deliveries of [cargo] from
/// [from] to [to] pay [bonus] more until [until].
class MagSubsidy {
  MagSubsidy(this.from, this.to, this.cargo, this.until);
  final int from, to, until;
  final MagCargo cargo;
}

/// Unique orders of cities (CONT-11): each is offered once in a game.
const magUniqueOrders = <(String, String, MagCargo, int, int, int)>[
  // (id, title, cargo, amount, reward, city level)
  ('bells', 'Колокола для собора', MagCargo.steel, 60, 14000, 5),
  ('school', 'Кирпич для первой школы', MagCargo.bricks, 120, 12000, 5),
  ('fair', 'Хлеб к осенней ярмарке', MagCargo.bread, 150, 11000, 6),
  ('tram', 'Рельсы для трамвая', MagCargo.steel, 140, 26000, 7),
  ('theatre', 'Электроника для театра', MagCargo.electronics, 30, 34000, 8),
  ('plant', 'Станки для городского завода', MagCargo.machines, 20, 48000, 8),
  ('bridge', 'Сталь для большого моста', MagCargo.steel, 260, 52000, 9),
  ('tower', 'Станки для телебашни', MagCargo.machines, 40, 90000, 10),
];

/// Stage S21: biomes (MAP-09), subsidies (CONT-10), unique orders
/// (CONT-11).
extension MagWorldBiomes on MagWorld {
  // ---- MAP-09 ----

  /// A region's land, from what covers it.
  MagBiome biomeOf(int region) {
    final cached = _biomes[region];
    if (cached != null) return cached;
    final s = (size / 3).ceil();
    final x0 = (region % 3) * s, y0 = (region ~/ 3) * s;
    var forest = 0, hill = 0, water = 0, all = 0;
    for (var y = y0; y < math.min(size, y0 + s); y++) {
      for (var x = x0; x < math.min(size, x0 + s); x++) {
        all++;
        switch (map.at(x, y)) {
          case MagTerrain.forest:
            forest++;
          case MagTerrain.hill:
            hill++;
          case MagTerrain.river || MagTerrain.lake:
            water++;
          case MagTerrain.grass:
            break;
        }
      }
    }
    final b = hill > all * .08
        ? MagBiome.highlands
        : forest > all * .3
        ? MagBiome.taiga
        : water > all * .1
        ? MagBiome.lakes
        : forest < all * .16
        ? MagBiome.steppe
        : MagBiome.meadows;
    _biomes[region] = b;
    return b;
  }

  MagBiome biomeAt(int x, int y) => biomeOf(regionOf(x, y));

  static String biomeName(MagBiome b) => switch (b) {
    MagBiome.meadows => 'Луга',
    MagBiome.steppe => 'Степь',
    MagBiome.taiga => 'Тайга',
    MagBiome.highlands => 'Нагорье',
    MagBiome.lakes => 'Озёрный край',
  };

  /// What each land is good for (new companies only): steppe farms, taiga
  /// logging, highland mining +10%; meadows farms +5%.
  static String biomeBonus(MagBiome b) => switch (b) {
    MagBiome.meadows => 'фермы +5%',
    MagBiome.steppe => 'фермы +10%',
    MagBiome.taiga => 'лесозаготовки +10%',
    MagBiome.highlands => 'добыча +10%',
    MagBiome.lakes => 'пассажиры +10% к оплате',
  };

  double biomeFactor(MagIndustry i) {
    if (!biomesOn || i.spec.produces.isEmpty || i.town != null) return 1;
    final b = biomeAt(i.x, i.y);
    return switch ((b, i.kind)) {
      (MagBiome.steppe, MagIndustryKind.farm) => 1.1,
      (MagBiome.meadows, MagIndustryKind.farm) => 1.05,
      (MagBiome.taiga, MagIndustryKind.sawmill) => 1.1,
      (
        MagBiome.highlands,
        MagIndustryKind.mine ||
            MagIndustryKind.quarry ||
            MagIndustryKind.coalMine ||
            MagIndustryKind.clayPit,
      ) =>
        1.1,
      _ => 1,
    };
  }

  /// Lakeside settlements pay passengers more.
  double biomePayFactor(MagIndustry here, MagCargo c) =>
      biomesOn && c.people && biomeAt(here.x, here.y) == MagBiome.lakes
      ? 1.1
      : 1;

  // ---- CONT-10 ----

  /// Extra pay of a delivery under a subsidy.
  double subsidyFactor(MagIndustry? from, MagIndustry here, MagCargo c) {
    if (from == null) return 1;
    for (final s in subsidies) {
      if (s.from == from.id && s.to == here.id && s.cargo == c) {
        return 1 + MagRules.subsidyBonus;
      }
    }
    return 1;
  }

  /// Every few days a city of level 4+ offers a subsidy for a line from
  /// the nearest place that supplies something it buys.
  void _daySubsidies() {
    subsidies.removeWhere((s) => s.until <= tick);
    if (level < MagRules.subsidyLevel ||
        day % MagRules.subsidyEvery != 0 ||
        subsidies.length >= 3) {
      return;
    }
    final cities = settlements.where((t) => t.town!.level >= 4).toList();
    if (cities.isEmpty) return;
    final city = cities[_mixS(day, cities.length) % cities.length];
    final wants = city.accepts.where(cargoAvailable).toList()
      ..sort((a, b) => a.index - b.index);
    if (wants.isEmpty) return;
    final c = wants[_mixS(day + 7, wants.length) % wants.length];
    MagIndustry? best;
    for (final s in map.industries) {
      if (s.town != null || s.spec.stores || !s.supplies.contains(c)) continue;
      if (best == null || s.distanceTo(city) < best.distanceTo(city)) best = s;
    }
    if (best == null) return;
    if (subsidies.any((s) => s.to == city.id && s.cargo == c)) return;
    subsidies.add(
      MagSubsidy(
        best.id,
        city.id,
        c,
        tick + MagRules.subsidyDays * MagRules.ticksPerDay,
      ),
    );
    _say(
      '${city.name}: субсидия на перевозку «${magCargoWord(c)}» из ${best.name}',
    );
  }

  int _mixS(int a, int n) {
    var h = a * 2654435761 + map.seed * 40503 + n;
    h = (h ^ (h >> 15)) & 0x7fffffff;
    return h;
  }

  // ---- CONT-11 ----

  /// Offers each unique order once, to the biggest city of its level.
  void _offerUniques() {
    for (final (id, title, cargo, amount, reward, lvl) in magUniqueOrders) {
      if (uniqueOffered.contains(id) || !cargoAvailable(cargo)) continue;
      final cities = settlements.where((t) => t.town!.level >= lvl).toList()
        ..sort((a, b) => b.town!.population.compareTo(a.town!.population));
      if (cities.isEmpty) continue;
      final city = cities.first;
      uniqueOffered.add(id);
      deals.add(
        MagDeal(
          id: nextId++,
          kind: MagDealKind.region,
          cargo: cargo,
          to: city.id,
          amount: amount,
          reward: reward,
          deadline: tick + 60 * MagRules.ticksPerDay,
        )..story = '${city.name}: $title',
      );
      _say('Уникальный заказ: $title');
      _remember('Уникальный заказ города ${city.name}: $title');
      return; // one at a time
    }
  }

  // ---- Saves ----

  Map<String, Object> _saveBiomes() => {
    if (biomesOn) 'biomes': true,
    if (subsidies.isNotEmpty)
      'subsidies': [
        for (final s in subsidies) [s.from, s.to, s.cargo.name, s.until],
      ],
    if (uniqueOffered.isNotEmpty) 'uniques': uniqueOffered.toList()..sort(),
    if (!musicOn) 'music': false,
    if (!soundOn) 'sound': false,
  };

  void loadBiomes(Map<String, dynamic> j) {
    biomesOn = j['biomes'] as bool? ?? false;
    musicOn = j['music'] as bool? ?? true;
    soundOn = j['sound'] as bool? ?? true;
    for (final e in j['subsidies'] as List? ?? const []) {
      final l = e as List;
      subsidies.add(
        MagSubsidy(
          l[0] as int,
          l[1] as int,
          MagCargo.values.byName(l[2] as String),
          l[3] as int,
        ),
      );
    }
    uniqueOffered.addAll([
      for (final x in j['uniques'] as List? ?? const []) x as String,
    ]);
  }
}
