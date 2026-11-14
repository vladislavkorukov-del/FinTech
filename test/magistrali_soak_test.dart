import 'dart:convert';
import 'dart:math';

import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:flutter_test/flutter_test.dart';

/// A soak run (S20): a company played at random for 80 days on a real
/// road network — the cargo books balance every day, saves round-trip and
/// the error journal stays empty.
void main() {
  for (final seed in [1]) {
    test('soak $seed: random play keeps the books, saves and runs clean', () {
      final rnd = Random(seed);
      final w =
          MagWorld.start(MagRules.defaultSeed + seed, MagScenario.classic, true)
            ..money = 3000000
            ..xp = MagWorldProgress.xpFor(12);
      w.techs.addAll(MagTechTree.all.map((t) => t.id).take(25));
      final inds = w.map.industries.toList();
      // A real network: each place joined to its two nearest.
      w.regionsLocked = false;
      for (final a in inds) {
        final near = [...inds]
          ..sort((p, q) => a.distanceTo(p).compareTo(a.distanceTo(q)));
        for (final b in near.skip(1).take(2)) {
          final p = w.planRoad(a.x + a.size, a.y, b.x - 1, b.y, MagRoad.dirt);
          if (p.error == null) w.buildRoad(p);
        }
      }
      final errs = <String>{};
      for (var day = 0; day < 80; day++) {
        for (var k = 0; k < 4; k++) {
          final a = inds[rnd.nextInt(inds.length)];
          final b = inds[rnd.nextInt(inds.length)];
          switch (rnd.nextInt(9)) {
            case 0 || 1:
              if (a.distanceTo(b) < 30) {
                final p = w.planRoad(
                  a.x + a.size,
                  a.y,
                  b.x - 1,
                  b.y,
                  MagRoad.values[rnd.nextInt(3)],
                );
                if (p.error == null) w.buildRoad(p);
              }
            case 2:
              final c = inds[rnd.nextInt(inds.length)];
              w.createRoute([a.id, b.id, c.id]);
            case 3:
              final m = MagRules.trucks[rnd.nextInt(MagRules.trucks.length)];
              w.buyTruck(m.id);
            case 4:
              if (w.routes.isNotEmpty && w.vehicles.isNotEmpty) {
                final v = w.vehicles.values.elementAt(
                  rnd.nextInt(w.vehicles.length),
                );
                w.assign(
                  v.id,
                  w.routes.keys.elementAt(rnd.nextInt(w.routes.length)),
                );
              }
            case 5:
              for (final c in a.supplies) {
                w.createOrder(
                  cargo: c,
                  from: a.id,
                  to: b.id,
                  amount: 1 + rnd.nextInt(60),
                );
              }
              for (final o
                  in w.orders.active
                      .where((o) => o.status == MagOrderStatus.pending)
                      .toList()) {
                final free = w.vehicles.values.where(w.isFree).toList();
                if (free.isNotEmpty) {
                  w.assignOrder(o.id, free[rnd.nextInt(free.length)].id);
                }
              }
            case 6:
              w.buyIndustry(a.id);
              w.upgradeIndustry(a.id);
            case 7:
              w.openRegion(rnd.nextInt(9));
            default:
              break;
          }
        }
        try {
          w.step(MagRules.ticksPerDay);
        } catch (e, st) {
          errs.add('$e\n$st'.substring(0, 600));
          rethrow;
        }
        final total = w.totalCargo();
        for (final c in MagCargo.values) {
          expect(
            total[c] ?? 0,
            (w.created[c] ?? 0) - (w.destroyed[c] ?? 0),
            reason: '$c day $day',
          );
        }
        if (day % 40 == 39) {
          final back = magWorldFromJson(
            jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
          );
          expect(
            jsonEncode(back.toJson()),
            jsonEncode(w.toJson()),
            reason: 'save day $day',
          );
        }
      }
      expect(w.simErrors, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}
