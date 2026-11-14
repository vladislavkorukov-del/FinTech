part of 'world.dart';

/// Stage S19: rival companies (META-09) and taking them over (META-10),
/// stars of a megalopolis past level 10 (META-12), the collection of
/// vehicles (VEH-14, META-08), the sandbox (MAP-12), and the finish of
/// partial mechanics: reputation (CITY-12, CONT-09), research by
/// achievements (TECH-08), the soft crisis (FIN-16).
class MagRival {
  MagRival(this.name, this.color, this.base);
  final String name;
  final int color, base;
  final Set<int> claims = {};
  int money = 0;
}

extension MagWorldRivals on MagWorld {
  // ---- META-09 / META-10 ----

  static const _rivalNames = [
    ('«СибТранс»', 0xFF8E3B46),
    ('«Волга-Логистик»', 0xFF4A6FD8),
    ('«Уральские магистрали»', 0xFF8C6D3F),
  ];

  /// The rival serving [i], if any.
  MagRival? rivalAt(MagIndustry i) =>
      rivals.where((r) => r.claims.contains(i.id)).firstOrNull;

  /// Deliveries to a place a rival serves pay less (competition).
  double rivalFactor(MagIndustry i) =>
      rivalAt(i) == null ? 1 : 1 - MagRules.rivalCut;

  int rivalValue(MagRival r) =>
      MagRules.rivalBase +
      r.claims.length * MagRules.rivalPerClaim +
      r.money ~/ 2;

  void _dayRivals() {
    if (scenario == MagScenario.sandbox) return;
    if (rivals.isEmpty && level >= MagRules.rivalLevel && !rivalsMet) {
      rivalsMet = true;
      final far = [...settlements]
        ..sort(
          (a, b) => b
              .distanceTo(map.startFarm)
              .compareTo(a.distanceTo(map.startFarm)),
        );
      for (var k = 0; k < 2 && k < far.length; k++) {
        final (name, color) = _rivalNames[k];
        rivals.add(MagRival(name, color, far[k * 3 % far.length].id));
      }
      _say('На рынке появились конкуренты');
      _remember(
        'Появились конкуренты: ${rivals.map((r) => r.name).join(', ')}',
      );
    }
    for (final r in rivals) {
      r.money += r.claims.length * MagRules.rivalIncome;
      if (day % MagRules.rivalEvery != 0 || r.claims.length >= 12) continue;
      final base = map.industry(r.base);
      if (base == null) continue;
      final free = [
        for (final i in map.industries)
          if (i.town == null &&
              !i.owned &&
              !i.spec.stores &&
              (i.spec.produces.isNotEmpty || i.spec.converts.isNotEmpty) &&
              rivalAt(i) == null)
            i,
      ]..sort((a, b) => a.distanceTo(base).compareTo(b.distanceTo(base)));
      if (free.isNotEmpty) r.claims.add(free.first.id);
    }
  }

  /// Buys a rival out: its places become the company's.
  String? acquireRival(int index) {
    if (index < 0 || index >= rivals.length) return 'Нет такой компании';
    final r = rivals[index];
    final price = rivalValue(r);
    if (money < price) return 'Не хватает кредитов: нужно $price';
    _spend(price, 'acquisitions');
    for (final id in r.claims) {
      final i = map.industry(id);
      if (i == null || !forSale(i) || i.owned) continue;
      i
        ..owned = true
        ..since = tick
        ..invested += buyPrice(i) ~/ 2;
    }
    rivals.removeAt(index);
    _remember('Поглощена компания ${r.name}');
    _say('${r.name} теперь ваша');
    return null;
  }

  // ---- META-12: stars of a megalopolis ----

  int starsOf(MagIndustry t) => stars[t.id] ?? 0;

  void _dayStars() {
    for (final t in settlements) {
      final s = t.town!;
      if (s.level < 10 || starsOf(t) >= 5) continue;
      final recent = s.satisfaction.length < 3
          ? 0.0
          : s.satisfaction.reduce((a, b) => a + b) / s.satisfaction.length;
      if (recent < .8) continue;
      final d = (starDays[t.id] ?? 0) + 1;
      if (d >= MagRules.starDays) {
        starDays.remove(t.id);
        stars[t.id] = starsOf(t) + 1;
        s.population += s.population ~/ 10;
        _say('${t.name}: звезда мегаполиса ${starsOf(t)}');
        _remember('${t.name}: ${starsOf(t)}-я звезда мегаполиса');
      } else {
        starDays[t.id] = d;
      }
    }
  }

  // ---- CITY-12 / CONT-09: reputation ----

  /// A settlement that knows the company well pays more (up to +10%).
  double reputationBonus(MagIndustry t) => t.town == null
      ? 0
      : math.min(MagRules.reputationMax, t.town!.reputation / 5000);

  // ---- TECH-08: research by achievements ----

  /// Each achievement lowers the price of research by 1% (up to 20%).
  int techCost(MagTech t) =>
      (t.cost * (1 - math.min(.2, achieved.length * .01))).round();

  // ---- VEH-14 / META-08: the collection ----

  /// Every model the company has owned: the ones it bought since 1.91 and
  /// the ones in its fleet now.
  Set<String> get collected => {
    ...collection,
    ...vehicles.values.map((v) => v.model),
  };

  void _collect(MagTruckModel m) {
    collection.add(m.id);
    final n0 = collected.length;
    for (final (n, reward) in MagRules.collectionSteps) {
      if (n0 >= n && collectionPaid < n) {
        collectionPaid = n;
        _earn(reward, 'collection');
        _say('Коллекция: $n моделей! +$reward кр');
        _remember('Коллекция техники: $n моделей');
      }
    }
  }

  // ---- FIN-16: the soft crisis ----

  void _dayCrisis() {
    if (money >= 0) {
      negativeDays = 0;
      return;
    }
    negativeDays++;
    // An overdraft: the bank charges on the minus.
    final fee = (-money * MagRules.overdraftRate).ceil();
    if (fee > 0) _spend(fee, 'overdraft');
    if (negativeDays == MagRules.crisisDays) {
      _say(
        'Компания в минусе уже ${MagRules.crisisDays} дней — продайте лишнее или возьмите кредит',
      );
      _remember('Финансовый кризис');
    }
  }

  // ---- Saves ----

  Map<String, Object> _saveRivals() => {
    if (rivals.isNotEmpty || rivalsMet)
      'rivals': {
        'met': rivalsMet,
        'list': [
          for (final r in rivals)
            {
              'name': r.name,
              'color': r.color,
              'base': r.base,
              'money': r.money,
              'claims': r.claims.toList()..sort(),
            },
        ],
      },
    if (stars.isNotEmpty)
      'stars': {for (final e in stars.entries) '${e.key}': e.value},
    if (starDays.isNotEmpty)
      'starDays': {for (final e in starDays.entries) '${e.key}': e.value},
    if (collection.isNotEmpty)
      'collection': [collectionPaid, ...collection.toList()..sort()],
    if (negativeDays != 0) 'negativeDays': negativeDays,
  };

  void loadRivals(Map<String, dynamic> j) {
    final r = j['rivals'] as Map?;
    if (r != null) {
      rivalsMet = r['met'] as bool? ?? false;
      for (final m in r['list'] as List? ?? const []) {
        final x = m as Map;
        rivals.add(
          MagRival(x['name'] as String, x['color'] as int, x['base'] as int)
            ..money = x['money'] as int? ?? 0
            ..claims.addAll([for (final c in x['claims'] as List) c as int]),
        );
      }
    }
    for (final e in (j['stars'] as Map? ?? const {}).entries) {
      stars[int.parse('${e.key}')] = e.value as int;
    }
    for (final e in (j['starDays'] as Map? ?? const {}).entries) {
      starDays[int.parse('${e.key}')] = e.value as int;
    }
    final c = j['collection'] as List?;
    if (c != null && c.isNotEmpty) {
      collectionPaid = c.first as int;
      collection.addAll([for (final m in c.skip(1)) m as String]);
    }
    negativeDays = j['negativeDays'] as int? ?? 0;
  }
}
