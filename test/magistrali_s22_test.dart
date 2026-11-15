import 'dart:convert';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/magistrali_world.dart';

/// Stage S22 (1.94): a living world — seasons, weather, events, the
/// campaign — and aviation; saves.
void main() {
  MagWorld reload(MagWorld w) => magWorldFromJson(
    jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
  );

  test(
    'a living world: new companies and old saves; test worlds stay still',
    () {
      expect(MagWorld.start().livingWorld, isFalse);
      final w = MagWorld.start(MagRules.defaultSeed, MagScenario.classic, true);
      expect(w.livingWorld, isTrue);
      expect(reload(w).livingWorld, isTrue);
      expect(reload(MagWorld.start()).livingWorld, isFalse);
      // A save from before 1.94 has no flag: it comes alive.
      final old = MagWorld.start().toJson()..remove('living');
      expect(
        magWorldFromJson(
          jsonDecode(jsonEncode(old)) as Map<String, dynamic>,
        ).livingWorld,
        isTrue,
      );
    },
  );

  test('seasons and weather change harvests and speed', () {
    final w = motorStart()..livingWorld = true;
    final farm = w.map.startFarm;
    expect(w.season, MagSeason.spring);
    w.tick = 30 * MagRules.ticksPerDay;
    expect(w.season, MagSeason.summer);
    expect(w.seasonFactor(farm), 1.2);
    w.tick = 90 * MagRules.ticksPerDay;
    expect(w.season, MagSeason.winter);
    expect(w.seasonFactor(farm), .5);
    final kinds = <MagWeather>{};
    for (var d = 0; d < 120; d++) {
      w.tick = d * MagRules.ticksPerDay;
      kinds.add(w.weather);
      final v = w.vehicles.values.first;
      expect(w.weatherSpeed(v), inInclusiveRange(.5, 1));
    }
    expect(kinds.length, greaterThanOrEqualTo(3));
    w.livingWorld = false;
    expect(w.weather, MagWeather.clear);
    expect(w.seasonFactor(farm), 1);
  });

  test('events: strikes stop a plant, festivals and booms pay, fuel costs', () {
    final w = motorStart()..livingWorld = true;
    final plant = w.map.startPlant;
    w.events.add(
      MagEvent('strike', w.tick + MagRules.ticksPerDay * 2, place: plant.id),
    );
    expect(w.isStruck(plant), isTrue);
    final town = w.settlements.first;
    final before = w.marketFactor(town, MagCargo.food);
    w.events.add(
      MagEvent('festival', w.tick + 999, place: town.id, cargo: MagCargo.food),
    );
    expect(w.marketFactor(town, MagCargo.food), closeTo(before * 1.4, 1e-9));
    w.events.add(MagEvent('fuel', w.tick + 999));
    expect(w.fuelFactor, 1.4);
    final back = reload(w);
    expect(back.events.length, 3);
    w.step(MagRules.ticksPerDay * 3);
    expect(w.isStruck(plant), isFalse);
    // Over a few months events do come.
    final l = MagWorld.start(MagRules.defaultSeed, MagScenario.classic, true)
      ..xp = MagWorldProgress.xpFor(5)
      ..regionsLocked = false;
    var seen = 0;
    for (var d = 0; d < 90; d++) {
      l.step(MagRules.ticksPerDay);
      seen += l.events.length;
    }
    expect(seen, greaterThan(0));
  });

  test('the campaign: chapters pass in order and pay', () {
    final w = motorStart()
      ..livingWorld = true
      ..money = 1000000;
    expect(w.chapterIndex, 0);
    expect(w.chapter!.title, 'Первые шаги');
    w.buyTruck('pickup');
    w.buyTruck('pickup');
    final money = w.money;
    w.step(MagRules.ticksPerDay);
    expect(w.chapterIndex, 1);
    expect(
      w.money - money,
      greaterThanOrEqualTo(magChapters.first.reward - 500),
    );
    expect(reload(w).chapterIndex, 1);
  });

  test('aviation: airports, a plane flies straight and delivers', () {
    final w = MagWorld.start()
      ..money = 10000000
      ..xp = MagWorldProgress.xpFor(20);
    w.techs.addAll(['combustion', 'aviation']);
    final a = w.map.startFarm, b = w.settlements.first;
    int? strip(MagIndustry p) {
      for (var d = 1; d <= 3; d++) {
        for (var y = p.top - d; y <= p.bottom + d; y++) {
          for (var x = p.left - d; x <= p.right + d; x++) {
            if (!w.map.inside(x, y)) continue;
            final c = w.cellOf(x, y);
            if (w.airportBlocker(c, p.id) == null) return c;
          }
        }
      }
      return null;
    }

    final ca = strip(a)!, cb = strip(b)!;
    expect(w.buildAirport(ca, a.id), isNull);
    expect(w.buildAirport(cb, b.id), isNull);
    expect(w.airPath([ca], b)!.last, cb);
    w.createRoute([a.id, b.id]);
    final route = w.routes.keys.last;
    expect(w.buyTruck('biplane'), isNull);
    final plane = w.vehicles.values.last;
    expect(plane.spec.air, isTrue);
    expect(w.assign(plane.id, route), isNull);
    expect(w.canCarry(plane, MagCargo.passengers), isTrue);
    w.step(MagRules.ticksPerDay);
    expect(plane.onMap, isTrue);
    final mid = reload(w);
    expect(mid.airports, w.airports);
    expect(mid.vehicles[plane.id]!.spec.air, isTrue);
    w.step(MagRules.ticksPerDay * 4);
    expect(plane.trips, greaterThan(0));
    expect(w.simErrors, isEmpty);
  });
}
