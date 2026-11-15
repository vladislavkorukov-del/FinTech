part of 'world.dart';

/// A town's mortgage programme (MORT-01): the money lent to families, when
/// it ends and how much has come back.
class MagMortgage {
  MagMortgage(this.town, this.amount, this.until, [this.returned = 0]);
  final int town, amount, until;
  int returned;

  /// What the programme brings back in all.
  int get total => (amount * MagRules.mortgageReturn).round();
}

/// Stage S25: container terminals and container ships (PORT-01, PORT-02),
/// rail signals (SIG-01), road interchanges (JCT-01), town mortgages
/// (MORT-01) and night shifts (NIGHT-01).
extension MagWorldPorts on MagWorld {
  // ---- PORT-01 / PORT-02 ----

  bool get containersUnlocked => techs.contains('containers');

  String? containerTerminalBlocker(int cell) {
    if (!containersUnlocked) {
      return 'Терминалы откроет технология «Контейнерные перевозки»';
    }
    if (!ports.containsKey(cell)) return 'Терминал строится в порту';
    if (terminals2.contains(cell)) return 'Терминал уже построен';
    return null;
  }

  String? buildContainerTerminal(int cell) {
    final why = containerTerminalBlocker(cell);
    if (why != null) return why;
    if (money < MagRules.containerTerminalPrice) {
      return 'Не хватает кредитов: нужно ${MagRules.containerTerminalPrice}';
    }
    _spend(MagRules.containerTerminalPrice, 'ports', source: 'industry');
    terminals2.add(cell);
    _say('Контейнерный терминал построен: краны грузят суда втрое быстрее');
    return null;
  }

  /// Units a vehicle loads per tick where it stands (a container terminal
  /// loads vessels three times faster).
  int handleAt(MagVehicle v) =>
      ((v.spec.water && terminals2.contains(v.cell)
                  ? handleRate * MagRules.terminalHandling
                  : handleRate) *
              hubHandling(v)) // S26: yards and hubs
          .round();

  /// A container ship calls only where there is a terminal (null: it can
  /// run [routeId]).
  String? containerRouteBlocker(int routeId) {
    final r = routes[routeId];
    if (r == null) return null;
    for (final id in r.stops) {
      final i = map.industry(id);
      if (i == null || !portCells(i).any(terminals2.contains)) {
        return 'У «${i?.name ?? '—'}» нет контейнерного терминала';
      }
    }
    return null;
  }

  // ---- SIG-01 ----

  bool get signalsUnlocked => techs.contains('signalling');

  String? toggleSignal(int cell) {
    if (signals.remove(cell)) {
      roadVersion++;
      return null;
    }
    if (!signalsUnlocked) {
      return 'Сигналы откроет технология «Железнодорожная сигнализация»';
    }
    if (rails[cell] == 0) return 'Сигнал ставится на путь';
    if (stations.containsKey(cell)) return 'На станции сигнал не нужен';
    if (money < MagRules.signalPrice) {
      return 'Не хватает кредитов: нужно ${MagRules.signalPrice}';
    }
    _spend(MagRules.signalPrice, 'rails');
    signals.add(cell);
    roadVersion++;
    return null;
  }

  /// The block ahead of a train standing at a signal: its path up to the
  /// next signal or station (that cell too).
  List<int> blockAhead(MagVehicle v) {
    final out = <int>[];
    for (var k = v.pathIndex + 1; k < v.path.length; k++) {
      final c = v.path[k];
      out.add(c);
      if (signals.contains(c) || stations.containsKey(c)) break;
      if (out.length >= MagRules.signalBlock) break;
    }
    return out;
  }

  /// At a signal a train waits while another train is in the block ahead
  /// (red); after a long wait it goes on by the usual rules, so a badly
  /// placed signal never stops a line for ever.
  bool _signalRed(MagVehicle v) {
    if (!v.spec.rail || !signals.contains(v.cell)) return false;
    if (v.blocked >= 3 * MagRules.trainWaitTicks) return false;
    final block = blockAhead(v).toSet();
    final busy = _trainCells(v).any(block.contains);
    if (busy) {
      v.blocked++;
    } else {
      v.blocked = 0;
    }
    return busy;
  }

  /// Is the signal at [cell] red now (for drawing)?
  bool signalRed(int cell) {
    final t = vehicles.values
        .where((v) => v.spec.rail && v.onMap && v.cell == cell)
        .firstOrNull;
    if (t == null || t.state != MagVehicleState.driving) return false;
    final block = blockAhead(t).toSet();
    return _trainCells(t).any(block.contains);
  }

  // ---- JCT-01 ----

  bool get interchangesUnlocked => techs.contains('interchanges');

  int _roadsAround(int cell) {
    var n = 0;
    for (var d = 0; d < 4; d++) {
      if (hasRoad(cx(cell) + MagDir.dx[d], cy(cell) + MagDir.dy[d])) n++;
    }
    return n;
  }

  String? interchangeBlocker(int cell) {
    if (!interchangesUnlocked) {
      return 'Развязки откроет технология «Развязки»';
    }
    if (roads[cell] == 0) return 'Развязка строится на дороге';
    if (interchanges.contains(cell)) return 'Развязка уже построена';
    if (_roadsAround(cell) < 3 && rails[cell] == 0) {
      return 'Развязка нужна на перекрёстке или переезде';
    }
    return null;
  }

  String? buildInterchange(int cell) {
    final why = interchangeBlocker(cell);
    if (why != null) return why;
    if (money < MagRules.interchangePrice) {
      return 'Не хватает кредитов: нужно ${MagRules.interchangePrice}';
    }
    _spend(MagRules.interchangePrice, 'roads');
    interchanges.add(cell);
    roadVersion++;
    _say('Развязка построена: пробок здесь больше не будет');
    return null;
  }

  String? removeInterchange(int cell) {
    if (!interchanges.remove(cell)) return 'Здесь нет развязки';
    roadVersion++;
    return null;
  }

  /// No jams at an interchange or right next to it.
  bool freeFlow(int cell) {
    if (interchanges.isEmpty) return false;
    if (interchanges.contains(cell)) return true;
    for (var d = 0; d < 4; d++) {
      final x = cx(cell) + MagDir.dx[d], y = cy(cell) + MagDir.dy[d];
      if (map.inside(x, y) && interchanges.contains(cellOf(x, y))) {
        return true;
      }
    }
    return false;
  }

  // ---- MORT-01 ----

  bool get mortgageUnlocked => techs.contains('mortgage');

  MagMortgage? mortgageOf(MagIndustry i) =>
      mortgages.where((m) => m.town == i.id).firstOrNull;

  int mortgagePrice(MagIndustry i) =>
      MagRules.mortgagePerLevel * (i.town?.level ?? 1);

  String? startMortgage(int townId) {
    final i = map.industry(townId);
    if (i == null || i.town == null) return 'Ипотека — для поселений';
    if (!mortgageUnlocked) return 'Ипотеку откроет технология «Ипотека»';
    if (mortgageOf(i) != null) return 'Программа здесь уже идёт';
    final price = mortgagePrice(i);
    if (money < price) return 'Не хватает кредитов: нужно $price';
    _spend(price, 'mortgage', source: 'industry', sourceId: i.id);
    mortgages.add(
      MagMortgage(
        i.id,
        price,
        tick + MagRules.mortgageDays * MagRules.ticksPerDay,
      ),
    );
    i.town!.remember(tick, 'Ипотечная программа: семьи покупают жильё');
    _say('«${i.name}»: ипотека запущена — город растёт быстрее');
    return null;
  }

  /// Population growth with a mortgage programme running.
  double mortgageFactor(MagIndustry i) =>
      mortgages.isEmpty || mortgageOf(i) == null ? 1 : MagRules.mortgageGrowth;

  // ---- NIGHT-01 ----

  bool get nightUnlocked => techs.contains('nightshift');

  String? setNightShift(int placeId, bool on) {
    final i = map.industry(placeId);
    if (i == null || !i.owned || i.town != null || i.spec.stores) {
      return 'Ночная смена — для своих предприятий';
    }
    if (!on) {
      nightShifts.remove(placeId);
      return null;
    }
    if (!nightUnlocked) {
      return 'Ночные смены откроет технология «Ночные смены»';
    }
    nightShifts.add(placeId);
    _say('«${i.name}»: ночная смена — выработка +30%');
    return null;
  }

  double nightBonusOf(MagIndustry i) =>
      nightShifts.isNotEmpty && nightShifts.contains(i.id) && i.owned
      ? MagRules.nightBonus
      : 0;

  /// A night shift's wages a day.
  int nightWageOf(MagIndustry i) => MagRules.nightWage * i.size * i.size;

  // ---- The day ----

  void _dayPorts() {
    // Places sold or lost drop their night shift.
    nightShifts.removeWhere((id) => map.industry(id)?.owned != true);
    for (final id in nightShifts) {
      final i = map.industry(id)!;
      _spend(nightWageOf(i), 'night_wages', source: 'industry', sourceId: id);
      i.costs += nightWageOf(i);
    }
    if (day % MagRules.daysPerMonth != 0) return;
    // Families pay the mortgage back month by month.
    final months = MagRules.mortgageDays ~/ MagRules.daysPerMonth;
    for (final m in mortgages.toList()) {
      final part = math.min(m.total - m.returned, (m.total / months).ceil());
      if (part > 0) {
        m.returned += part;
        _earn(part, 'mortgage_in');
      }
      if (m.returned >= m.total || tick >= m.until && m.returned >= m.total) {
        mortgages.remove(m);
        _say('Ипотека в «${map.industry(m.town)?.name}» выплачена');
      }
    }
  }

  // ---- Saves ----

  Map<String, Object> _savePorts() => {
    if (terminals2.isNotEmpty) 'cterminals': terminals2.toList()..sort(),
    if (signals.isNotEmpty) 'signals': signals.toList()..sort(),
    if (interchanges.isNotEmpty) 'interchanges': interchanges.toList()..sort(),
    ..._saveHubs(), // S26
    ..._saveWays(), // S27
    if (nightShifts.isNotEmpty) 'night': nightShifts.toList()..sort(),
    if (mortgages.isNotEmpty)
      'mortgages': [
        for (final m in mortgages) [m.town, m.amount, m.until, m.returned],
      ],
  };

  void loadPorts(Map<String, dynamic> j) {
    loadHubs(j); // S26
    loadWays(j); // S27
    List<int> ints(String k) => [
      for (final v in j[k] as List? ?? const []) v as int,
    ];
    terminals2.addAll(ints('cterminals').where(ports.containsKey));
    signals.addAll(
      ints('signals').where((c) => c >= 0 && c < rails.length && rails[c] != 0),
    );
    interchanges.addAll(
      ints(
        'interchanges',
      ).where((c) => c >= 0 && c < roads.length && roads[c] != 0),
    );
    nightShifts.addAll(ints('night').where((id) => map.industry(id) != null));
    for (final raw in j['mortgages'] as List? ?? const []) {
      final l = raw as List;
      if (map.industry(l[0] as int)?.town == null) continue;
      mortgages.add(
        MagMortgage(l[0] as int, l[1] as int, l[2] as int, l[3] as int),
      );
    }
  }
}
