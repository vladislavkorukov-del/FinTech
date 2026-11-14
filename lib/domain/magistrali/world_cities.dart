part of 'world.dart';

/// Cities, levels 4 and up (master plan stage 6): a specialization made by
/// what the company brings, a market that pays more for its own cargo, a
/// demand of the week, and big city orders with a deadline. Everything
/// here is worked out from the tick and the place, so it is the same after
/// a reload and never touches the regular contracts' random numbers.
extension MagWorldCities on MagWorld {
  bool isCity(MagIndustry i) =>
      i.town != null && i.town!.level >= MagTowns.cityLevel;

  /// Cities on the map.
  Iterable<MagIndustry> get cities => settlements.where(isCity);

  int _mix(int a, int b) {
    var n = a * 73856093 ^ b * 19349663 ^ map.seed * 83492791;
    n = (n ^ (n >> 13)) * 1274126177;
    return (n ^ (n >> 16)) & 0x7fffffff;
  }

  /// The cargo a city wants most this week (null: not a city, or nothing
  /// it takes can be made).
  MagCargo? weeklyDemand(MagIndustry i) {
    if (!isCity(i)) return null;
    final list = i.accepts.where(cargoAvailable).toList()
      ..sort((a, b) => a.index - b.index);
    if (list.isEmpty) return null;
    final week = day ~/ MagTowns.daysPerWeek;
    return list[_mix(week, i.id) % list.length];
  }

  /// Days left of this week's demand.
  int get weekDaysLeft => MagTowns.daysPerWeek - day % MagTowns.daysPerWeek;

  /// How much more a delivery of [c] to [i] pays: a bigger market, the
  /// city's own cargo, a trade city, the demand of the week.
  double marketFactor(MagIndustry i, MagCargo c) {
    final t = i.town;
    if (t == null) return 1;
    var k = (1 + t.spec.payBonus) * glutFactor(i, c) + deficitBonusOf(i, c);
    if (isCity(i)) {
      if (MagTowns.favoured(t.specialization).contains(c)) {
        k += MagTowns.favouredBonus;
      }
      if (t.specialization == MagSpecialization.trade) k += MagTowns.tradeBonus;
      if (weeklyDemand(i) == c) k += MagTowns.weeklyBonus;
    }
    return k;
  }

  /// A flooded market pays less (stage S11, BIZ-09): nothing off until the
  /// recent deliveries pass half the market's appetite, up to 30% off at
  /// twice it. The flood fades day by day.
  double glutFactor(MagIndustry i, MagCargo c) {
    final t = i.town;
    if (t == null) return 1;
    final appetite = math.max(30, (t.spec.needs[c] ?? 2) * 12).toDouble();
    final s = (t.glut[c] ?? 0) / appetite;
    return 1 - MagRules.glutDiscount * ((s - .5) / 1.5).clamp(0.0, 1.0);
  }

  /// A shortage pays more (stage S11, BIZ-11): what a settlement needs and
  /// has run out of in its pantry.
  double deficitBonusOf(MagIndustry i, MagCargo c) {
    final t = i.town;
    if (t == null || !needsOf(i).containsKey(c)) return 0;
    return (t.pantry[c] ?? 0) == 0 ? MagRules.deficitBonus : 0;
  }

  /// A settlement becoming a city takes the specialization of what it was
  /// brought most (it keeps its old one if nothing was brought).
  void _chooseSpecialization(MagIndustry i) {
    final t = i.town!;
    final s = MagTowns.specializationFor(t.received);
    if (s == null || s == t.specialization) return;
    t.specialization = s;
    t.remember(tick, 'Специализация: ${MagTowns.cityAdjective(s)} город');
  }

  // ---- City orders ----

  /// Open city orders (they live with the contracts, with a deadline).
  Iterable<MagContract> get cityOrders =>
      contracts.where((c) => c.deadline != null);

  /// Regular contracts only.
  Iterable<MagContract> get regularContracts =>
      contracts.where((c) => c.deadline == null);

  /// Each day: orders past their deadline go, cities without an order get
  /// a new one once they are ready.
  void _dayCities() {
    for (final c in cityOrders.toList()) {
      if (tick <= c.deadline!) continue;
      contracts.remove(c);
      final i = map.industry(c.to);
      final t = i?.town;
      if (t != null) {
        t
          ..orderAt = tick + MagRules.ticksPerDay * MagRules.cityOrderPause
          ..remember(tick, 'Городской заказ не выполнен в срок');
      }
      _say('${i?.name ?? 'Город'}: срок заказа истёк');
    }
    for (final i in cities.toList()) {
      final t = i.town!;
      if (tick < t.orderAt) continue;
      if (cityOrders.any((c) => c.to == i.id)) continue;
      final o = _cityOrder(i);
      if (o != null) {
        contracts.add(o);
        t.remember(tick, 'Городской заказ: ${o.amount} ед. за ${o.reward} кр');
      }
    }
  }

  /// A big order of a city: its own cargo first, more and better paid the
  /// bigger the city; a deadline long enough for a cart convoy.
  MagContract? _cityOrder(MagIndustry i) {
    final t = i.town!;
    final all = i.accepts.where(cargoAvailable).toList()
      ..sort((a, b) => a.index - b.index);
    if (all.isEmpty) return null;
    final own = all
        .where(MagTowns.favoured(t.specialization).contains)
        .toList();
    final pick = _mix(tick, i.id);
    final list = own.isNotEmpty && pick % 3 != 0 ? own : all;
    final cargo = list[pick % list.length];
    final l = t.level;
    final amount = 50 + 25 * (l - MagTowns.cityLevel) + (pick >> 4) % 40;
    final days = 20 + 4 * (l - MagTowns.cityLevel);
    final reward =
        (amount * MagRules.cargoRate[cargo]! * 32 * (1 + .15 * (l - 3)) +
                250 * l)
            .round();
    return MagContract(
      id: nextId++,
      cargo: cargo,
      to: i.id,
      amount: amount,
      reward: reward,
      xp: reward ~/ 10,
      deadline: tick + days * MagRules.ticksPerDay,
    );
  }
}
