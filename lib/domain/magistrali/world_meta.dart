part of 'world.dart';

/// Achievements (META-02), the company's chronicle (META-05), loans
/// (FIN-15), the fleet in bulk (VEH-11) and replacing old vehicles
/// (VEH-12) — stage S15.
extension MagWorldMeta on MagWorld {
  // ---- META-05: the chronicle ----

  /// Writes an event into the company's chronicle (the last 200 kept).
  void _remember(String text) {
    chronicle.add((tick, text));
    if (chronicle.length > 200) chronicle.removeAt(0);
  }

  // ---- META-02: achievements ----

  /// Progress towards an achievement, from the world as it is.
  int achievementProgress(String id) {
    int count(bool Function(int c) f) {
      var n = 0;
      for (var c = 0; c < size * size; c++) {
        if (f(c)) n++;
      }
      return n;
    }

    return switch (id) {
      'roads50' || 'roads300' => count((c) => roads[c] != 0),
      'bridge' => count(
        (c) => roads[c] != 0 && map.at(cx(c), cy(c)) == MagTerrain.river,
      ),
      'tunnel' => count(
        (c) =>
            (roads[c] != 0 || rails[c] != 0) &&
            map.at(cx(c), cy(c)) == MagTerrain.hill,
      ),
      'trips100' || 'trips1000' => deliveries,
      'fleet5' || 'fleet20' => vehicles.length,
      'routes5' => routes.length,
      'earn100k' || 'earn1m' => earnedTotal,
      'level10' || 'level20' => level,
      'owner3' => map.industries.where((i) => i.owned).length,
      'city' =>
        settlements.where((i) => isCity(i) && i.town!.origin < 4).length,
      'rail' => count((c) => rails[c] != 0),
      'ship' => vehicles.values.where((v) => v.spec.water).length,
      'people500' =>
        (delivered[MagCargo.passengers] ?? 0) +
            (delivered[MagCargo.workers] ?? 0),
      'tech15' => techs.length,
      'mega' => map.industries.where((i) => i.projectDone).length,
      _ => 0,
    };
  }

  /// Pays the achievements reached (once each); run once a day.
  void _checkAchievements() {
    if (scenario == MagScenario.sandbox) return; // MAP-12: no rewards
    for (final a in MagAchievements.all) {
      if (achieved.containsKey(a.id)) continue;
      if (achievementProgress(a.id) < a.goal) continue;
      achieved[a.id] = tick;
      _earn(a.reward, 'achievements');
      _gainXp(a.reward ~/ 20);
      _say('Достижение «${a.title}»! +${a.reward} кр');
      _remember('Достижение «${a.title}»');
    }
  }

  // ---- FIN-15: loans ----

  /// The most the bank lends now (grows with the company level).
  int get loanLimit => MagRules.loanBase + level * MagRules.loanPerLevel;

  /// Interest of a day on the debt.
  int get dailyInterest => (debt * MagRules.loanRate).ceil();

  String? takeLoan(int amount) {
    if (amount <= 0) return 'Сумма должна быть больше нуля';
    if (debt + amount > loanLimit) {
      return 'Банк даст не больше ${loanLimit - debt} кр';
    }
    debt += amount;
    money += amount;
    journal.add(
      tick: tick,
      kind: MagEntryKind.financing,
      category: 'loan',
      amount: amount,
    );
    _say('Кредит получен: $amount кр');
    _remember('Кредит $amount кр');
    return null;
  }

  String? repayLoan(int amount) {
    final n = math.min(amount, debt);
    if (n <= 0) return 'Долга нет';
    if (money < n) return 'Не хватает кредитов';
    debt -= n;
    money -= n;
    journal.add(
      tick: tick,
      kind: MagEntryKind.financing,
      category: 'loan_repay',
      amount: -n,
    );
    _say(debt == 0 ? 'Кредит погашен' : 'Погашено $n кр');
    if (debt == 0) _remember('Кредит погашен');
    return null;
  }

  void _dayLoan() {
    if (debt > 0) _spend(dailyInterest, 'interest');
  }

  // ---- VEH-11: the fleet in bulk ----

  /// What repairing every worn vehicle costs now.
  int get repairAllCost =>
      vehicles.values.fold(0, (s, v) => s + serviceCost(v));

  /// Repairs every worn vehicle the money allows; returns how many.
  int repairAll() {
    var n = 0;
    for (final v in vehicles.values) {
      final c = serviceCost(v);
      if (c == 0 || money < c) continue;
      if (service(v.id) == null) n++;
    }
    return n;
  }

  /// Puts every free vehicle that can go there on route [routeId].
  int assignIdle(int routeId) {
    var n = 0;
    for (final v in vehicles.values.toList()) {
      if (v.routeId != null || v.orderId != null) continue;
      if (assign(v.id, routeId) == null) n++;
    }
    return n;
  }

  // ---- VEH-12: replacing old vehicles ----

  /// The best model of the same kind the company can buy now that carries
  /// more than [v] (null: it is the best already).
  MagTruckModel? newerModelFor(MagVehicle v) {
    bool same(MagTruckModel m) =>
        m.rail == v.spec.rail &&
        m.water == v.spec.water &&
        m.passengers == v.spec.passengers &&
        (v.spec.rail || v.spec.water || v.spec.passengers
            ? true
            : m.horse == v.spec.horse || !m.horse);
    MagTruckModel? best;
    for (final m in MagRules.trucks) {
      if (!same(m) || m.id == v.model) continue;
      final cap = m.rail ? m.wagonCapacity : m.capacity;
      final now = v.spec.rail ? v.spec.wagonCapacity : v.spec.capacity;
      if (cap <= now) continue;
      if (level < m.level || !_canBuyModel(m)) continue;
      if (best == null ||
          (m.rail ? m.wagonCapacity : m.capacity) >
              (best.rail ? best.wagonCapacity : best.capacity)) {
        best = m;
      }
    }
    return best;
  }

  bool _canBuyModel(MagTruckModel m) {
    if (m.water) {
      return shippingUnlocked && (m.id != 'freighter' || shipyardUnlocked);
    }
    if (m.rail) return railsUnlocked && (m.id != 'diesel' || dieselUnlocked);
    if (!m.horse && !motorUnlocked) return false;
    return m.tech == null || techs.contains(m.tech);
  }

  /// Price of replacing [v] by [newerModelFor] (its sale counted in).
  int? replaceCost(MagVehicle v) {
    final m = newerModelFor(v);
    if (m == null) return null;
    return math.max(0, m.price + m.wagonPrice * v.wagons - valueOf(v));
  }

  /// Sells [id] and buys the newer model in its place, on its route.
  String? replaceVehicle(int id) {
    final v = vehicles[id];
    if (v == null) return 'Нет такой машины';
    final m = newerModelFor(v);
    if (m == null) return 'Новее модели пока нет';
    final cost = replaceCost(v)!;
    if (money < cost) return 'Не хватает кредитов: нужно $cost';
    final route = v.routeId;
    final name = v.name;
    sellTruck(id);
    final why = buyTruck(m.id);
    if (why != null) return why;
    final n = vehicles.values.last..name = name;
    if (route != null) assign(n.id, route);
    _remember('$name заменён на ${m.name}');
    return null;
  }

  /// Replaces every vehicle that has a newer model, while money allows.
  int replaceAllOutdated() {
    var n = 0;
    for (final v in vehicles.values.toList()) {
      final c = replaceCost(v);
      if (c == null || money < c) continue;
      if (replaceVehicle(v.id) == null) n++;
    }
    return n;
  }

  // ---- Saves ----

  Map<String, Object> _saveMeta() => {
    if (achieved.isNotEmpty) 'achieved': Map.of(achieved),
    if (chronicle.isNotEmpty)
      'chronicle': [
        for (final (t, s) in chronicle) [t, s],
      ],
    if (debt != 0) 'debt': debt,
  };

  void loadMeta(Map<String, dynamic> j) {
    for (final e in (j['achieved'] as Map? ?? const {}).entries) {
      final t = e.value;
      if (MagAchievements.byId('${e.key}') == null || t is! int) {
        throw const FormatException('Bad achievement in Magistrali save');
      }
      achieved['${e.key}'] = t;
    }
    for (final raw in j['chronicle'] as List? ?? const []) {
      final p = raw as List;
      chronicle.add((p[0] as int, p[1] as String));
    }
    final d = j['debt'] ?? 0;
    if (d is! int || d < 0) throw const FormatException('Bad debt');
    debt = d;
  }
}
