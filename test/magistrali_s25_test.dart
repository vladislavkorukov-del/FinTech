import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage S25 (1.97): container terminals and ships, rail signals, road
/// interchanges, town mortgages, night shifts; saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  MagWorld rich() => MagWorld.start()
    ..money = 2000000
    ..xp = MagWorldProgress.xpFor(16);

  test('a container terminal loads vessels faster; boxes pay more', () {
    final w = rich();
    w.techs.addAll(['stud', 'steam', 'shipping', 'combustion', 'shipyard']);
    final water = w.waterMask;
    int? port;
    for (var c = 0; c < water.length && port == null; c++) {
      if (water[c] == 1 && w.portTargets(c).isNotEmpty) port = c;
    }
    final place = w.portTargets(port!).first;
    expect(w.buildPort(port, place.id), isNull);
    expect(w.containerTerminalBlocker(port), contains('Контейнерные'));
    expect(w.buyTruck('boxship'), contains('Контейнерные'));
    w.techs.add('containers');
    expect(w.containerTerminalBlocker(port + 0), isNull);
    final money = w.money;
    expect(w.buildContainerTerminal(port), isNull);
    expect(w.money, money - MagRules.containerTerminalPrice);
    expect(w.buildContainerTerminal(port), contains('уже'));
    expect(w.buyTruck('boxship'), isNull);
    final ship = w.vehicles.values.last;
    expect(w.canCarry(ship, MagCargo.grain), isTrue);
    expect(w.canCarry(ship, MagCargo.oil), isFalse);
    expect(w.canCarry(ship, MagCargo.passengers), isFalse);
    expect(w.cargoPayFactor(ship, MagCargo.grain), MagRules.containerBonus);
    ship.cell = port;
    expect(w.handleAt(ship), w.handleRate * MagRules.terminalHandling);
    ship.cell = port == 0 ? 1 : port - 1;
    expect(w.handleAt(ship), w.handleRate);
    ship.cell = -1;
    expect(reload(w).terminals2, contains(port));
  });

  test('a container ship runs only between terminals', () {
    final w = rich();
    w.techs.addAll([
      'stud',
      'steam',
      'shipping',
      'combustion',
      'shipyard',
      'containers',
      'dispatch',
    ]);
    final water = w.waterMask;
    final served = <int, int>{};
    for (var c = 0; c < water.length && served.length < 2; c++) {
      if (water[c] != 1) continue;
      for (final i in w.portTargets(c)) {
        if (!served.containsValue(i.id) && !served.containsKey(c)) {
          served[c] = i.id;
          break;
        }
      }
    }
    expect(served.length, 2);
    for (final e in served.entries) {
      expect(w.buildPort(e.key, e.value), isNull);
    }
    expect(w.createRoute(served.values.toList()), isNull);
    final r = w.routes.keys.last;
    expect(w.containerRouteBlocker(r), contains('терминала'));
    for (final c in served.keys) {
      expect(w.buildContainerTerminal(c), isNull);
    }
    expect(w.containerRouteBlocker(r), isNull);
  });

  test('a signal is red while another train is in the block ahead', () {
    final w = rich();
    w.techs.addAll(['stud', 'steam']);
    final a = w.map.startFarm;
    final x0 = a.right + 3, y0 = a.bottom + 3;
    // A straight stretch of track somewhere free.
    MagRoadPlan? plan;
    for (var dy = 0; dy < 30 && plan == null; dy++) {
      final p = w.planRail(x0, y0 + dy, x0 + 10, y0 + dy);
      if (p.error == null && p.cells.length == 11) plan = p;
    }
    expect(w.buildRail(plan!), isNull);
    final cells = plan.cells;
    expect(w.toggleSignal(cells[2]), contains('сигнализация'));
    w.techs.add('signalling');
    expect(w.toggleSignal(cells[2]), isNull);
    expect(w.toggleSignal(cells[7]), isNull);
    expect(w.signals, {cells[2], cells[7]});
    expect(w.buyTruck('steam'), isNull);
    expect(w.buyTruck('steam'), isNull);
    final t1 = w.vehicles.values.toList()[w.vehicles.length - 2];
    final t2 = w.vehicles.values.last;
    t1
      ..cell = cells[2]
      ..path = cells
      ..pathIndex = 2
      ..state = MagVehicleState.driving;
    expect(w.blockAhead(t1), cells.sublist(3, 8));
    expect(w.signalRed(cells[2]), isFalse);
    t2.cell = cells[5];
    expect(w.signalRed(cells[2]), isTrue);
    t2.cell = cells[9];
    expect(w.signalRed(cells[2]), isFalse);
    for (final t in [t1, t2]) {
      t
        ..cell = -1
        ..path = const []
        ..pathIndex = 0
        ..state = MagVehicleState.garage;
    }
    expect(reload(w).signals, {cells[2], cells[7]});
    // A signal comes off again for free.
    expect(w.toggleSignal(cells[7]), isNull);
    expect(w.signals, {cells[2]});
  });

  test('an interchange stops jams at a crossing and next to it', () {
    final w = rich();
    w.techs.add('combustion');
    final f = w.map.startFarm, p = w.map.startPlant;
    final plan = w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt);
    expect(w.buildRoad(plan), isNull);
    final c = plan.cells[plan.cells.length ~/ 2];
    expect(w.interchangeBlocker(c), contains('Развязки'));
    w.techs.add('interchanges');
    expect(w.interchangeBlocker(c), contains('перекрёстке'));
    // A crowded crossing: the jam slows vehicles until an interchange.
    w.traffic[c] = 1000;
    expect(w.congestionOf(c), lessThan(1));
    w.interchanges.add(c);
    expect(w.congestionOf(c), 1);
    w.traffic[plan.cells[plan.cells.length ~/ 2 + 1]] = 1000;
    expect(w.congestionOf(plan.cells[plan.cells.length ~/ 2 + 1]), 1);
    expect(reload(w).interchanges, contains(c));
    expect(w.removeInterchange(c), isNull);
    expect(w.congestionOf(c), lessThan(1));
  });

  test('a mortgage: the town grows faster and the money comes back', () {
    final w = rich();
    final town = w.map.industries.firstWhere((i) => i.town != null);
    expect(w.startMortgage(town.id), contains('Ипотеку'));
    expect(w.startMortgage(w.map.startFarm.id), contains('поселений'));
    w.techs.add('mortgage');
    final price = w.mortgagePrice(town);
    expect(price, MagRules.mortgagePerLevel * town.town!.level);
    final money = w.money;
    expect(w.startMortgage(town.id), isNull);
    expect(w.money, money - price);
    expect(w.startMortgage(town.id), contains('уже'));
    expect(w.mortgageFactor(town), MagRules.mortgageGrowth);
    expect(reload(w).mortgageOf(town)!.amount, price);
    w.step(MagRules.ticksPerDay * MagRules.daysPerMonth);
    final back =
        w.months.fold(0, (s, m) => s + (m.income['mortgage_in'] ?? 0)) +
        (w.month.income['mortgage_in'] ?? 0);
    expect(back, greaterThan(0));
    w.step(MagRules.ticksPerDay * (MagRules.mortgageDays + 5));
    expect(w.mortgages, isEmpty);
    expect(w.mortgageFactor(town), 1);
  });

  test('a night shift: +30% output for wages every day', () {
    final w = rich();
    final farm = w.map.startFarm;
    farm.owned = true;
    final k = w.outputFactor(farm);
    expect(w.setNightShift(farm.id, true), contains('Ночные'));
    w.techs.add('nightshift');
    expect(w.setNightShift(farm.id, true), isNull);
    expect(w.outputFactor(farm), closeTo(k + MagRules.nightBonus, 1e-9));
    expect(reload(w).nightShifts, contains(farm.id));
    w.step(MagRules.ticksPerDay * 2);
    final wages =
        w.months.fold(0, (s, m) => s + (m.expense['night_wages'] ?? 0)) +
        (w.month.expense['night_wages'] ?? 0);
    expect(wages, greaterThan(0));
    expect(w.setNightShift(farm.id, false), isNull);
    expect(w.outputFactor(farm), closeTo(k, 1e-9));
    final town = w.map.industries.firstWhere((i) => i.town != null);
    expect(w.setNightShift(town.id, true), contains('своих'));
  });
}
