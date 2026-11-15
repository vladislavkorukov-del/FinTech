part of 'world.dart';

/// A futures contract on a cargo (FUT-01): deliver [units] by [until] and
/// get the margin back with a premium; miss it and the margin is lost.
class MagFuture {
  MagFuture(this.cargo, this.units, this.until, this.margin, [this.done = 0]);
  final MagCargo cargo;
  final int units, until, margin;
  int done;

  int get payout =>
      (margin / MagRules.futureMargin * MagRules.futurePremium).round();
}

/// Stage S26: metro in big cities (METRO-01), marshalling yards at
/// stations (HUB-01), freight hubs at warehouses (HUB-02), cargo futures
/// (FUT-01), tourist excursions (TOUR-03).
extension MagWorldHubs on MagWorld {
  // ---- METRO-01 ----

  bool get metroUnlocked => techs.contains('metro');

  String? metroBlocker(MagIndustry i) {
    if (i.town == null) return 'Метро строят в городах';
    if (!metroUnlocked) return 'Метро откроет технология «Метрополитен»';
    if (i.town!.level < MagRules.metroLevel) {
      return 'Метро — с уровня «Региональный центр»';
    }
    if (metros.contains(i.id)) return 'Метро уже работает';
    return null;
  }

  String? buildMetro(int townId) {
    final i = map.industry(townId);
    if (i == null) return 'Нет такого города';
    final why = metroBlocker(i);
    if (why != null) return why;
    if (money < MagRules.metroPrice) {
      return 'Не хватает кредитов: нужно ${MagRules.metroPrice}';
    }
    _spend(MagRules.metroPrice, 'metro', source: 'industry', sourceId: i.id);
    metros.add(i.id);
    i.town!.remember(tick, 'Открыт метрополитен');
    _say('«${i.name}»: метро открыто — больше пассажиров и быстрый рост');
    return null;
  }

  /// More people travel and the city grows faster with a metro.
  double metroFactor(MagIndustry i) =>
      metros.isNotEmpty && metros.contains(i.id) ? MagRules.metroPassengers : 1;
  double metroGrowth(MagIndustry i) =>
      metros.isNotEmpty && metros.contains(i.id)
      ? MagRules.metroGrowth *
            (1 + MagRules.metroLineGrowth * math.min(3, metroLinesOf(i)))
      : 1;

  /// Fares the metro brings a day.
  int metroFares(MagIndustry i) =>
      (i.town!.population * MagRules.metroFare).round();

  // ---- HUB-01 ----

  bool get yardsUnlocked => techs.contains('yards');

  String? yardBlocker(int cell) {
    if (!yardsUnlocked) {
      return 'Сортировочные станции откроет технология «Сортировочные станции»';
    }
    if (!stations.containsKey(cell)) return 'Строится на станции';
    if (yards.contains(cell)) return 'Сортировочная уже есть';
    return null;
  }

  String? buildYard(int cell) {
    final why = yardBlocker(cell);
    if (why != null) return why;
    if (money < MagRules.yardPrice) {
      return 'Не хватает кредитов: нужно ${MagRules.yardPrice}';
    }
    _spend(MagRules.yardPrice, 'rails');
    yards.add(cell);
    _say('Сортировочная горка построена: поезда грузятся вдвое быстрее');
    return null;
  }

  // ---- HUB-02 ----

  bool get hubsUnlocked => techs.contains('hubs');

  String? hubBlocker(MagIndustry i) {
    if (!i.spec.stores) return 'Хаб строится на складе';
    if (!hubsUnlocked) return 'Хабы откроет технология «Грузовые хабы»';
    if (hubs.contains(i.id)) return 'Склад уже хаб';
    return null;
  }

  String? buildHub(int warehouseId) {
    final i = map.industry(warehouseId);
    if (i == null) return 'Нет такого склада';
    final why = hubBlocker(i);
    if (why != null) return why;
    if (money < MagRules.hubPrice) {
      return 'Не хватает кредитов: нужно ${MagRules.hubPrice}';
    }
    _spend(MagRules.hubPrice, 'warehouses', source: 'industry', sourceId: i.id);
    hubs.add(i.id);
    _say('«${i.name}» стал грузовым хабом: +50% места, погрузка ×2');
    return null;
  }

  double hubRoom(MagIndustry w) =>
      hubs.isNotEmpty && hubs.contains(w.id) ? MagRules.hubRoom : 1;

  /// Loading is faster at a marshalling yard (trains) and at a freight hub
  /// (every vehicle).
  double hubHandling(MagVehicle v) {
    var k = 1.0;
    if (v.spec.rail && yards.contains(v.cell)) k *= MagRules.yardHandling;
    if (hubs.isNotEmpty && v.routeId != null) {
      final here = _stopOf(v, v.stop);
      if (here != null && hubs.contains(here.id)) k *= MagRules.hubHandling;
    }
    return k;
  }

  // ---- FUT-01 ----

  bool get futuresOpen => level >= MagRules.futuresLevel;

  /// The margin for [units] of [c].
  int futureMarginOf(MagCargo c, int units) =>
      (units * MagRules.cargoValue[c]! * MagRules.futureMargin).ceil();

  String? buyFuture(MagCargo c, int units) {
    if (!futuresOpen) {
      return 'Фьючерсы — с ${MagRules.futuresLevel} уровня компании';
    }
    if (!cargoAvailable(c) || c.people) return 'Этот груз на карте не делают';
    if (futures.length >= MagRules.futuresMax) {
      return 'Не больше ${MagRules.futuresMax} контрактов сразу';
    }
    final m = futureMarginOf(c, units);
    if (money < m) return 'Не хватает кредитов: залог $m';
    _spend(m, 'futures', cargo: c, units: units);
    futures.add(
      MagFuture(c, units, tick + MagRules.futureDays * MagRules.ticksPerDay, m),
    );
    _say('Фьючерс: $units ед. за ${MagRules.futureDays} дн.');
    return null;
  }

  /// A delivery counts towards the futures on its cargo.
  void _countFutures(MagCargo c, int n) {
    for (final f in futures.toList()) {
      if (f.cargo != c) continue;
      f.done = math.min(f.units, f.done + n);
      if (f.done >= f.units) {
        futures.remove(f);
        _earn(f.payout, 'futures_in', cargo: c, units: f.units);
        _say('Фьючерс исполнен: +${f.payout} кр');
      }
    }
  }

  // ---- TOUR-03 ----

  bool _resort(MagIndustry? i) =>
      i != null &&
      (i.kind == MagIndustryKind.lakeResort ||
          i.kind == MagIndustryKind.skiResort);

  String? excursionBlocker(int routeId) {
    final r = routes[routeId];
    if (r == null) return 'Нет маршрута';
    if (!techs.contains('tourism')) {
      return 'Экскурсии откроет технология «Туризм»';
    }
    if (r.stops.length < 3) return 'Экскурсия — от трёх остановок';
    if (!r.stops.any((id) => _resort(map.industry(id)))) {
      return 'В экскурсии нужен курорт';
    }
    return null;
  }

  String? setExcursion(int routeId, bool on) {
    if (!on) {
      excursions.remove(routeId);
      return null;
    }
    final why = excursionBlocker(routeId);
    if (why != null) return why;
    excursions.add(routeId);
    _say('Маршрут стал экскурсией: туристы платят ×${MagRules.excursionPay}');
    return null;
  }

  double excursionFactor(MagVehicle v) =>
      excursions.isNotEmpty && excursions.contains(v.routeId)
      ? MagRules.excursionPay
      : 1;

  // ---- The day ----

  void _dayHubs() {
    excursions.removeWhere((id) => !routes.containsKey(id));
    hubs.removeWhere((id) => map.industry(id)?.spec.stores != true);
    yards.removeWhere((c) => !stations.containsKey(c));
    for (final id in metros) {
      final i = map.industry(id);
      if (i?.town == null) continue;
      final fares = metroFares(i!);
      if (fares > 0) {
        _earn(fares, 'metro_fares', source: 'industry', sourceId: id);
      }
    }
    for (final f in futures.where((f) => f.until <= tick).toList()) {
      futures.remove(f);
      _say('Фьючерс не исполнен: залог ${f.margin} кр потерян');
    }
  }

  // ---- Saves ----

  Map<String, Object> _saveHubs() => {
    if (metros.isNotEmpty) 'metros': metros.toList()..sort(),
    if (yards.isNotEmpty) 'yards': yards.toList()..sort(),
    if (hubs.isNotEmpty) 'hubs': hubs.toList()..sort(),
    if (excursions.isNotEmpty) 'excursions': excursions.toList()..sort(),
    if (futures.isNotEmpty)
      'futures': [
        for (final f in futures)
          [f.cargo.index, f.units, f.until, f.margin, f.done],
      ],
  };

  void loadHubs(Map<String, dynamic> j) {
    List<int> ints(String k) => [
      for (final v in j[k] as List? ?? const []) v as int,
    ];
    metros.addAll(ints('metros').where((id) => map.industry(id)?.town != null));
    yards.addAll(ints('yards').where(stations.containsKey));
    hubs.addAll(ints('hubs').where((id) => map.industry(id) != null));
    excursions.addAll(ints('excursions').where(routes.containsKey));
    for (final raw in j['futures'] as List? ?? const []) {
      final l = raw as List;
      final k = l[0] as int;
      if (k < 0 || k >= MagCargo.values.length) continue;
      futures.add(
        MagFuture(
          MagCargo.values[k],
          l[1] as int,
          l[2] as int,
          l[3] as int,
          l[4] as int,
        ),
      );
    }
  }
}
