import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S21 (1.93): machine tools (PROD-10), biomes (MAP-09), subsidies
/// (CONT-10), unique city orders (CONT-11); saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  void give(MagWorld w, Map<MagCargo, int> into, MagCargo c, int n) {
    into[c] = (into[c] ?? 0) + n;
    w.created[c] = (w.created[c] ?? 0) + n;
  }

  test(
    'machine-tool works: research, build, steel and parts make machines',
    () {
      final w = motorStart()
        ..money = 10000000
        ..xp = MagWorldProgress.xpFor(12);
      final spec = MagRules.industries[MagIndustryKind.machineWorks]!;
      expect(spec.converts[MagCargo.steel], MagCargo.machines);
      final f = w.map.startFarm;
      late int x, y;
      var found = false;
      for (var d = 3; d < 30 && !found; d++) {
        for (final (dx, dy) in [(d, 0), (0, d), (-d, 0), (0, -d)]) {
          x = f.x + dx;
          y = f.y + dy;
          if (w.buildIndustry(MagIndustryKind.machineWorks, x, y) == null) {
            found = true;
            break;
          }
          if (!w.techs.contains('machinetools')) break;
        }
        if (!found && !w.techs.contains('machinetools')) {
          w.techs.addAll(['metallurgy', 'kilns', 'machinery', 'machinetools']);
        }
      }
      expect(found, isTrue);
      final works = w.map.industries.last;
      expect(works.kind, MagIndustryKind.machineWorks);
      expect(w.cargoAvailable(MagCargo.machines), isTrue);
      give(w, works.input, MagCargo.steel, 20);
      give(w, works.input, MagCargo.parts, 10);
      w.step(MagRules.ticksPerDay);
      expect(works.stock[MagCargo.machines] ?? 0, greaterThan(0));
      // Cities from level 6 buy them.
      expect(MagTowns.marketGoods(6), contains(MagCargo.machines));
      expect(MagTowns.marketGoods(5), isNot(contains(MagCargo.machines)));
      expect(reload(w).map.industries.last.kind, MagIndustryKind.machineWorks);
    },
  );

  test('biomes: every region has a land; bonuses only in new companies', () {
    final w = MagWorld.start(MagRules.defaultSeed, MagScenario.classic, true);
    expect(w.biomesOn, isTrue);
    final lands = {for (var r = 0; r < 9; r++) w.biomeOf(r)};
    expect(lands.length, greaterThanOrEqualTo(2));
    final farm = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.farm,
    );
    final b = w.biomeAt(farm.x, farm.y);
    final k = w.biomeFactor(farm);
    expect(
      k,
      b == MagBiome.steppe
          ? 1.1
          : b == MagBiome.meadows
          ? 1.05
          : 1,
    );
    expect(reload(w).biomesOn, isTrue);
    final old = MagWorld.start();
    expect(old.biomesOn, isFalse);
    expect(old.biomeFactor(farm), 1);
  });

  test('subsidies: a city pays 40% more on its line for a while', () {
    final w = motorStart()..xp = MagWorldProgress.xpFor(6);
    final t = w.settlements.first;
    t.town!.level = 4;
    for (var d = 0; d < MagRules.subsidyEvery * 2; d++) {
      w.step(MagRules.ticksPerDay);
    }
    expect(w.subsidies, isNotEmpty);
    final s = w.subsidies.first;
    final from = w.map.industry(s.from)!, to = w.map.industry(s.to)!;
    expect(w.subsidyFactor(from, to, s.cargo), 1 + MagRules.subsidyBonus);
    expect(w.subsidyFactor(to, from, s.cargo), 1);
    final back = reload(w);
    expect(back.subsidies.length, w.subsidies.length);
    w.step(MagRules.subsidyDays * MagRules.ticksPerDay + 1);
    expect(w.subsidies.where((x) => x.until <= w.tick), isEmpty);
  });

  test('unique orders: once each, to the biggest city of its level', () {
    final w = motorStart()..xp = MagWorldProgress.xpFor(8);
    final t = w.settlements.first;
    t.town!.level = 5;
    w.step(MagRules.ticksPerDay);
    final first = w.deals.where((d) => d.story != null && d.to == t.id);
    expect(first, isNotEmpty);
    expect(w.uniqueOffered, isNotEmpty);
    final count = w.uniqueOffered.length;
    w.step(MagRules.ticksPerDay);
    // One a day at most, never the same twice.
    expect(w.uniqueOffered.length, lessThanOrEqualTo(count + 1));
    final ids = w.deals.where((d) => d.story != null).map((d) => d.story);
    expect(ids.toSet().length, ids.length);
    expect(reload(w).uniqueOffered, w.uniqueOffered);
  });
}
