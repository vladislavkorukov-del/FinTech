import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S10: cities of levels 8–10 (CITY-02), «От хутора до мегаполиса»
/// once, for a settlement founded as a hamlet, kept for ever (META-03,
/// META-04), megaprojects commissioned by a city and built by real
/// deliveries (META-06, CONT-08); saves.
void main() {
  void expectBalanced(MagWorld w) {
    final total = w.totalCargo();
    for (final c in MagCargo.values) {
      expect(
        total[c] ?? 0,
        (w.created[c] ?? 0) - (w.destroyed[c] ?? 0),
        reason: '$c at tick ${w.tick}',
      );
    }
  }

  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  /// Grows a settlement one level for real (stock, people, a day).
  bool growOnce(MagWorld w, MagIndustry i) {
    final t = i.town!;
    final before = t.level;
    for (final e in t.spec.development.entries) {
      if (!w.cargoAvailable(e.key)) continue;
      final have = t.devStock[e.key] ?? 0;
      if (have < e.value) {
        t.devStock[e.key] = e.value;
        w.created[e.key] = (w.created[e.key] ?? 0) + e.value - have;
      }
    }
    t
      ..population = MagTowns.of(t.level + 1).population
      ..satisfaction.addAll(List.filled(7, 1.0));
    w.step(MagRules.ticksPerDay);
    return t.level > before;
  }

  test('levels 8–10: industrial needs, growth and what they open', () {
    for (final l in [8, 9, 10]) {
      final s = MagTowns.of(l);
      expect(
        s.needs.keys,
        containsAll([MagCargo.steel, MagCargo.parts, MagCargo.bricks]),
      );
      expect(s.opens.join(' '), contains('Мегапроект'));
    }
    expect(MagTowns.of(7).development, contains(MagCargo.steel));
    expect(MagTowns.of(8).development, contains(MagCargo.parts));
    expect(MagTowns.of(9).development, contains(MagCargo.steel));
    // An old map has none of these goods: its cities do not ask for them.
    final old = MagWorld(map: MagMap.generate(MagRules.defaultSeed));
    final city = old.cities.first..town!.level = 9;
    expect(old.needsOf(city).keys, isNot(contains(MagCargo.parts)));
  });

  test('a settlement remembers how it was founded', () {
    final w = MagWorld.start();
    final hamlet = w.settlements.firstWhere((i) => i.town!.level == 1);
    final village = w.settlements.firstWhere((i) => i.name == 'Луговое');
    expect(hamlet.town!.origin, 1);
    expect(village.town!.origin, 2);
    hamlet.town!.level = 4;
    final b = reload(w);
    expect(b.map.industry(hamlet.id)!.town!.origin, 1);
    final old = MagWorld(map: MagMap.generate(MagRules.defaultSeed));
    expect(old.cities.first.town!.origin, 6);
  });

  test('«От хутора до мегаполиса»: once, for a hamlet, kept for ever', () {
    final w = MagWorld.start()..money = 1000000;
    // A village (founded at level 2) becoming a megalopolis earns nothing.
    final village = w.settlements.firstWhere((i) => i.name == 'Луговое');
    var grew = true;
    while (village.town!.level < 10 && grew) {
      grew = growOnce(w, village);
    }
    if (village.town!.level == 10) expect(w.firstMegapolis, isNull);
    // A hamlet that makes it all the way earns it.
    MagIndustry? winner;
    for (final h in w.settlements.where((i) => i.town!.origin == 1)) {
      var ok = true;
      while (h.town!.level < 10 && ok) {
        ok = growOnce(w, h);
      }
      if (h.town!.level == 10) {
        winner = h;
        break;
      }
    }
    expect(winner, isNotNull, reason: 'no hamlet had room to grow');
    expect(w.firstMegapolis, winner!.id);
    expect(winner.town!.cells.length, 37);
    final paid = w.journal.entries.where((e) => e.category == 'achievement');
    expect(paid.single.amount, MagRules.megapolisReward);
    expect(paid.single.kind, MagEntryKind.revenue);
    expect(w.earnedRewards, contains('magistrali:megapolis:v1'));
    expect(
      winner.town!.history.map((e) => e.text),
      contains('Достижение «От хутора до мегаполиса»!'),
    );
    // A second one does not pay again; the mark survives a save.
    for (final h in w.settlements.where(
      (i) => i.town!.origin == 1 && i != winner,
    )) {
      var ok = true;
      while (h.town!.level < 10 && ok) {
        ok = growOnce(w, h);
      }
    }
    expect(
      w.journal.entries.where((e) => e.category == 'achievement').length,
      1,
    );
    final b = reload(w);
    expect(
      (b.firstMegapolis, b.firstMegapolisTick),
      (w.firstMegapolis, w.firstMegapolisTick),
    );
    expectBalanced(w);
  });

  test('a megaproject: commissioned, built by deliveries, pays once', () {
    final w = motorStart()..money = 1000000;
    final city = w.settlements.firstWhere((i) => i.name == 'Луговое');
    city.town!.level = 6;
    expect(w.megaprojectBlocker('bridge', city.id), 'Городу нужен 7 уровень');
    city.town!.level = 7;
    expect(w.megaprojectBlocker('bridge', city.id), isNull);
    final money = w.money;
    expect(w.startMegaproject('bridge', city.id), isNull);
    expect(w.money, money - 15000);
    expect(w.journal.entries.last.category, 'megaprojects');
    expect(w.journal.entries.last.kind, MagEntryKind.capex);
    expect(w.startMegaproject('bridge', city.id), 'Этот мегапроект уже начат');
    final site = w.siteOf('bridge')!;
    expect(site.kind, MagIndustryKind.megaproject);
    expect(
      site.projectNeeds.keys,
      containsAll([MagCargo.steel, MagCargo.stone]),
    );
    expect(site.accepts, site.projectNeeds.keys.toSet());
    // Everything but the stone has arrived already.
    for (final e in site.projectNeeds.entries) {
      if (e.key != MagCargo.stone) site.projectProgress[e.key] = e.value;
    }
    expect(site.accepts, {MagCargo.stone});
    expect(w.roomOf(site, MagCargo.stone), site.projectNeeds[MagCargo.stone]);
    // Most of the stone too; the last 20 come by truck from the nearest
    // quarry, along a road.
    site.projectProgress[MagCargo.stone] =
        site.projectNeeds[MagCargo.stone]! - 20;
    const need = 20;
    final quarries =
        w.map.industries.where((i) => i.kind == MagIndustryKind.quarry).toList()
          ..sort((x, y) => x.distanceTo(site).compareTo(y.distanceTo(site)));
    MagIndustry? quarry;
    for (final q in quarries) {
      var linked = false;
      for (var y = q.top - 1; y <= q.bottom + 1 && !linked; y++) {
        for (var x = q.left - 1; x <= q.right + 1 && !linked; x++) {
          for (var yy = site.top - 1; yy <= site.bottom + 1 && !linked; yy++) {
            for (
              var xx = site.left - 1;
              xx <= site.right + 1 && !linked;
              xx++
            ) {
              final p = w.planRoad(x, y, xx, yy, MagRoad.dirt);
              if (p.error == null && w.buildRoad(p) == null) {
                linked = w.connected(q, site);
              }
            }
          }
        }
      }
      if (linked) {
        quarry = q;
        break;
      }
    }
    expect(quarry, isNotNull);
    quarry!.stock[MagCargo.stone] = (quarry.stock[MagCargo.stone] ?? 0) + need;
    w.created[MagCargo.stone] = (w.created[MagCargo.stone] ?? 0) + need;
    w.createRoute([quarry.id, site.id]);
    w.assign(w.vehicles.values.single.id, w.routes.keys.last);
    final payBefore = w.bonus(MagBonus.roadSpeed);
    for (var k = 0; k < 40 * 60 && !site.projectDone; k++) {
      w.step();
    }
    expect(
      site.projectDone,
      isTrue,
      reason:
          'progress ${site.projectProgress} of ${site.projectNeeds}, truck ${w.vehicles.values.single.state} trips ${w.vehicles.values.single.trips}',
    );
    final paid = w.journal.entries.where((e) => e.category == 'infrastructure');
    expect(paid.single.amount, MagMegaprojects.byId('bridge')!.reward);
    expect(w.bonus(MagBonus.roadSpeed), payBefore + .1);
    expect(site.accepts, isEmpty);
    expect(
      city.town!.history.map((e) => e.text).join(' '),
      contains('Большой мост'),
    );
    // Saved and loaded: the site, its progress and its effect.
    final b = reload(w);
    final sb = b.siteOf('bridge')!;
    expect(sb.projectDone, isTrue);
    expect(sb.projectNeeds, site.projectNeeds);
    expect(b.bonus(MagBonus.roadSpeed), w.bonus(MagBonus.roadSpeed));
    w.step(MagRules.ticksPerDay * 3);
    expect(
      w.journal.entries.where((e) => e.category == 'infrastructure').length,
      1,
    );
    expectBalanced(w);
  });
}
