part of 'world.dart';

/// Stage S23: disasters and repairs (DIS-01, DIS-02), the stock exchange
/// (STK-01, STK-02).
extension MagWorldMarket on MagWorld {
  // ---- DIS-01 / DIS-02 ----

  /// Can a vehicle drive over this road cell (not broken)?
  bool roadOpen(int c) => roads[c] != 0 && !damaged.containsKey(c);

  /// Days until a broken cell is mended by itself: quicker near a depot.
  int repairDaysAt(int c) {
    final x = cx(c), y = cy(c);
    final crew = depots.any(
      (d) => (cx(d) - x).abs() + (cy(d) - y).abs() <= MagRules.crewReach,
    );
    return crew ? MagRules.crewRepairDays : MagRules.repairDays;
  }

  /// The price to mend a broken cell at once.
  int repairPrice(int c) =>
      MagRules.repairBase * math.max(1, roads[c]).toInt() +
      (map.at(cx(c), cy(c)) == MagTerrain.river ? MagRules.repairBase * 3 : 0);

  String? repairRoad(int c) {
    if (!damaged.containsKey(c)) return 'Дорога цела';
    final price = repairPrice(c);
    if (money < price) return 'Не хватает кредитов: нужно $price';
    _spend(price, 'repairs');
    damaged.remove(c);
    roadVersion++;
    return null;
  }

  /// Mends every broken cell the company can pay for.
  int repairAllRoads() {
    var n = 0;
    for (final c in damaged.keys.toList()..sort()) {
      if (repairRoad(c) == null) n++;
    }
    return n;
  }

  void _dayDisasters() {
    // Mended by crews in time.
    final mended = [
      for (final e in damaged.entries)
        if (e.value <= tick) e.key,
    ];
    for (final c in mended) {
      damaged.remove(c);
    }
    if (mended.isNotEmpty) roadVersion++;
    if (!livingWorld || level < MagRules.disasterLevel) return;
    final w = weather;
    if (w != MagWeather.rain && w != MagWeather.storm) return;
    var h = map.seed * 2246822519 + day * 3266489917 + 7;
    h = (h ^ (h >> 13)) & 0x7fffffff;
    if (h % 100 >= (w == MagWeather.storm ? 30 : 12)) return;
    // Cells nobody stands on or is about to enter.
    final busy = <int>{};
    for (final v in vehicles.values) {
      if (!v.onMap) continue;
      busy.add(v.cell);
      if (v.pathIndex + 1 < v.path.length) busy.add(v.path[v.pathIndex + 1]);
    }
    final bridges = <int>[], plain = <int>[];
    for (var c = 0; c < roads.length; c++) {
      if (!roadOpen(c) || busy.contains(c)) continue;
      (map.at(cx(c), cy(c)) == MagTerrain.river ? bridges : plain).add(c);
    }
    final hit = <int>[];
    if (w == MagWeather.rain && bridges.isNotEmpty) {
      hit.add(bridges[(h >> 7) % bridges.length]);
    } else if (plain.isNotEmpty) {
      for (var k = 0; k < 2; k++) {
        hit.add(plain[((h >> (5 + k * 4)) + k * 977) % plain.length]);
      }
    }
    if (hit.isEmpty) return;
    for (final c in hit) {
      damaged[c] = tick + repairDaysAt(c) * MagRules.ticksPerDay;
    }
    roadVersion++;
    _say(
      w == MagWeather.rain
          ? 'Паводок размыл мост — объезд или ремонт'
          : 'Буря повредила дорогу: ${hit.length} кл.',
    );
    _remember(
      w == MagWeather.rain ? 'Паводок размыл мост' : 'Буря повредила дороги',
    );
  }

  // ---- STK-01 ----

  /// A share of the company: its value over a thousand shares.
  int get sharePrice => math.max(1, companyValue ~/ MagRules.shares);

  String? issueShares([int n = 100]) {
    if (ownShares - n < MagRules.controlShares) {
      return 'Нужно сохранить контроль: не меньше ${MagRules.controlShares} акций';
    }
    final pay = (n * sharePrice * .95).round();
    ownShares -= n;
    _earn(pay, 'shares');
    _remember('Выпущено $n акций: +$pay кр');
    return null;
  }

  String? buybackShares([int n = 100]) {
    if (ownShares + n > MagRules.shares) return 'Все акции уже ваши';
    final cost = (n * sharePrice * 1.05).round();
    if (money < cost) return 'Не хватает кредитов: нужно $cost';
    _spend(cost, 'buyback');
    ownShares += n;
    return null;
  }

  // ---- STK-02 ----

  int rivalSharePrice(MagRival r) =>
      math.max(1, rivalValue(r) ~/ MagRules.shares);

  int stakeIn(MagRival r) => rivalStakes[r.name] ?? 0;

  /// Buys shares of a rival; past half of them the rival is the company's.
  String? buyRivalShares(int index, [int n = 100]) {
    if (index < 0 || index >= rivals.length) return 'Нет такой компании';
    final r = rivals[index];
    final cost = (n * rivalSharePrice(r) * 1.05).round();
    if (money < cost) return 'Не хватает кредитов: нужно $cost';
    _spend(cost, 'stocks');
    final stake = stakeIn(r) + n;
    rivalStakes[r.name] = stake;
    if (stake >= MagRules.controlShares) {
      for (final id in r.claims) {
        final i = map.industry(id);
        if (i == null || !forSale(i) || i.owned) continue;
        i
          ..owned = true
          ..since = tick;
      }
      rivals.removeAt(index);
      rivalStakes.remove(r.name);
      _remember('${r.name} поглощена через биржу');
      _say('Контрольный пакет: ${r.name} теперь ваша');
    }
    return null;
  }

  /// Each day: the price goes into the history; once a month dividends —
  /// paid to outside holders, received from rival stakes.
  void _dayStocks() {
    priceHistory.add(sharePrice);
    if (priceHistory.length > 60) priceHistory.removeAt(0);
    if (day % MagRules.daysPerMonth != 0) return;
    final profit = month.profit;
    if (ownShares < MagRules.shares && profit > 0) {
      final out =
          (profit * .3 * (MagRules.shares - ownShares) / MagRules.shares)
              .round();
      if (out > 0) _spend(out, 'dividends');
    }
    for (final r in rivals) {
      final get = (r.money * .05 * stakeIn(r) / MagRules.shares).round();
      if (get > 0) _earn(get, 'dividends_in');
    }
  }

  /// The day of the market and the weather's damage.
  void _dayMarket() {
    _dayDisasters();
    _dayStocks();
  }

  // ---- TOUR-01 / TOUR-02 ----

  /// Tourists pay more on the way to a resort: +60%, half as much again
  /// in its season (summer by a lake, winter in the mountains).
  double tourismFactor(MagIndustry here, MagCargo c) {
    if (!c.people) return 1;
    final lake = here.kind == MagIndustryKind.lakeResort;
    if (!lake && here.kind != MagIndustryKind.skiResort) return 1;
    final peak =
        livingWorld && season == (lake ? MagSeason.summer : MagSeason.winter);
    return MagRules.touristPay * (peak ? MagRules.touristPeak : 1);
  }

  // ---- Saves ----

  Map<String, Object> _saveMarket() => {
    if (damaged.isNotEmpty)
      'damaged': [
        for (final e
            in (damaged.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          [e.key, e.value],
      ],
    if (ownShares != MagRules.shares) 'ownShares': ownShares,
    if (rivalStakes.isNotEmpty) 'stakes': rivalStakes,
    if (priceHistory.isNotEmpty) 'prices': priceHistory,
  };

  void loadMarket(Map<String, dynamic> j) {
    for (final raw in j['damaged'] as List? ?? const []) {
      final l = raw as List;
      damaged[l[0] as int] = l[1] as int;
    }
    ownShares = j['ownShares'] as int? ?? MagRules.shares;
    for (final e in (j['stakes'] as Map? ?? const {}).entries) {
      rivalStakes['${e.key}'] = e.value as int;
    }
    priceHistory.addAll([
      for (final p in j['prices'] as List? ?? const []) p as int,
    ]);
  }
}
