import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/world/magistrali/mag_route_create.dart';
import 'package:finora/presentation/screens/world/magistrali/mag_screen.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/magistrali_store.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Stage S8 on screen, by real touches: draw track with a finger, put a
/// station by a place, buy a steam engine, couple a wagon, open a
/// station's sheet.
void main() {
  sqfliteFfiInit();
  late Directory dir;
  late FinanceRepository repo;
  late FinanceController c;
  setUp(() async {
    await initializeDateFormatting('ru');
    dir = await Directory.systemTemp.createTemp('mag-ui-');
    MagistraliStore.debugRoot = dir;
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/db',
    );
    await repo.save(
      const FinanceData(
        accounts: [Account(id: 'a', name: 'Карта', openingMinor: 100000)],
        members: [Member(id: 'me', name: 'Я')],
      ),
    );
    c = FinanceController(repo, _Quiet(), await repo.load());
    await c.syncWorld();
  });
  tearDown(() async {
    MagistraliStore.debugRoot = null;
    c.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, 'coffee'),
          home: home,
        ),
      ),
    );
  }

  Future<MagistraliScreenState> ready(WidgetTester tester) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final s = tester.stateList<MagistraliScreenState>(
        find.byType(MagistraliScreen),
      );
      if (s.isNotEmpty && s.first.maybeWorld != null) return s.first;
    }
    fail('Магистрали did not open');
  }

  Offset at(WidgetTester tester, MagistraliScreenState s, int x, int y) {
    final size = tester.getSize(find.byKey(const ValueKey('mag-map')));
    return s.camera.cellToScreen(x + .5, y + .5, size);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(195, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var k = 0; k < 20; k++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }

  testWidgets('S8: track, stations, a steam train with wagons', (tester) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world
      ..money = 500000
      ..xp = MagWorldProgress.xpFor(8)
      ..techs.addAll(['stud', 'steam']);
    s.changed();
    await settle(tester);
    final farm = w.map.startFarm, plant = w.map.startPlant;
    // Free cells by each place for the stations.
    int spot(MagIndustry i) {
      for (var y = i.top - 1; y <= i.bottom + 1; y++) {
        for (var x = i.left - 1; x <= i.right + 1; x++) {
          if (w.map.roadable(x, y) && w.map.industryAt(x, y) == null) {
            return w.cellOf(x, y);
          }
        }
      }
      fail('no spot');
    }

    final a = spot(farm), b = spot(plant);
    s.camera.zoom = 1;
    s.centerOn((w.cx(a) + w.cx(b)) / 2 + .5, (w.cy(a) + w.cy(b)) / 2 + .5);
    await tester.pump();
    await tap(tester, 'mag-tab-build');
    await tap(tester, 'mag-cat-rail');
    expect(s.tool, MagTool.rail);
    await tester.tapAt(at(tester, s, w.cx(a), w.cy(a)));
    await tester.pump();
    await tester.tapAt(at(tester, s, w.cx(b), w.cy(b)));
    await tester.pump();
    expect(find.textContaining('Ж/д путь'), findsWidgets);
    await tap(tester, 'mag-confirm-build');
    expect(w.rails[a], 1);
    expect(w.rails[b], 1);

    // Stations by a tap on the track.
    await tap(tester, 'mag-tool-station');
    for (final (cell, place) in [(a, farm), (b, plant)]) {
      await tester.tapAt(at(tester, s, w.cx(cell), w.cy(cell)));
      await tester.pump();
      expect(s.pendingStationPlace, place.id);
      await tap(tester, 'mag-confirm-build');
      expect(w.stations[cell], place.id);
    }
    await tap(tester, 'mag-tab-build'); // back to looking

    // A steam engine from the shop, a second wagon.
    await tap(tester, 'mag-tab-fleet');
    await tap(tester, 'mag-buy-steam');
    final t = w.vehicles.values.last;
    expect((t.spec.id, t.wagons), ('steam', 1));
    await tap(tester, 'mag-truck-${t.id}');
    await tap(tester, 'mag-wagons-plus');
    expect(t.wagons, 2);
    await closeSheet(tester);

    // The station's sheet.
    await tester.tapAt(at(tester, s, w.cx(a), w.cy(a)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('mag-station-sheet')), findsOneWidget);
    await closeSheet(tester);
    await settle(tester);
  });

  testWidgets('S9: a port by a tap, a barge, the port and track sheets', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world
      ..money = 500000
      ..xp = MagWorldProgress.xpFor(9)
      ..techs.addAll(['stud', 'steam', 'shipping']);
    s.changed();
    await settle(tester);
    // A water cell by some place.
    late int berth;
    late MagIndustry place;
    search:
    for (final i in w.map.industries) {
      for (var y = i.top - 2; y <= i.bottom + 2; y++) {
        for (var x = i.left - 2; x <= i.right + 2; x++) {
          if (!w.map.inside(x, y)) continue;
          final c = w.cellOf(x, y);
          if (w.isWater(c) && w.portTargets(c).first == i) {
            berth = c;
            place = i;
            break search;
          }
        }
      }
    }
    s.camera.zoom = 1;
    s.centerOn(w.cx(berth) + .5, w.cy(berth) + .5);
    await tester.pump();
    await tap(tester, 'mag-tab-build');
    await tap(tester, 'mag-cat-water');
    await tester.tapAt(at(tester, s, w.cx(berth), w.cy(berth)));
    await tester.pump();
    expect(s.pendingPortPlace, place.id);
    expect(find.textContaining('Порт у'), findsOneWidget);
    await tap(tester, 'mag-confirm-build');
    expect(w.ports[berth], place.id);
    await tap(tester, 'mag-tab-build'); // back to looking

    await tap(tester, 'mag-tab-fleet');
    await tap(tester, 'mag-buy-barge');
    expect(w.vehicles.values.last.spec.water, isTrue);
    await closeSheet(tester);

    await tester.tapAt(at(tester, s, w.cx(berth), w.cy(berth)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('mag-port-sheet')), findsOneWidget);
    await closeSheet(tester);

    // A piece of track: its sheet lights the stretch.
    final farm = w.map.startFarm;
    final x = farm.x - 3, y = farm.y + 4;
    expect(w.buildRail(w.planRail(x, y, x + 4, y)), isNull);
    s.centerOn(x + 2.5, y + .5);
    s.changed();
    await tester.pump();
    await tester.tapAt(at(tester, s, x + 2, y));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('mag-rail-sheet')), findsOneWidget);
    expect(s.overlay.plan.length, greaterThanOrEqualTo(5));
    await tap(tester, 'mag-rail-remove');
    expect(w.rails.every((r) => r == 0), isTrue);
    await settle(tester);
  });

  testWidgets(
    'S10: a megaproject from a city, the megalopolis badge, a route drawn',
    (tester) async {
      await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
      final s = await ready(tester);
      final w = s.world..money = 500000;
      final city = w.settlements.firstWhere((t) => t.name == 'Луговое');
      city.town!.level = 7;
      w.firstMegapolis = city.id; // as if it had grown from a hamlet
      // A truck on a route, selected: its way is drawn dashed (no errors).
      final farm = w.map.startFarm, plant = w.map.startPlant;
      w.buildRoad(
        w.planRoad(
          farm.x + farm.size,
          farm.y,
          plant.x - 1,
          plant.y,
          MagRoad.dirt,
        ),
      );
      w.createRoute([farm.id, plant.id]);
      w.assign(w.vehicles.values.single.id, w.routes.keys.single);
      w.step(30);
      s.overlay.vehicle = w.vehicles.keys.single;
      s.changed();
      s.centerOn(farm.centerX + 3, farm.centerY);
      for (var k = 0; k < 5; k++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      s.overlay.vehicle = null;

      // The city's sheet: the megalopolis badge and a megaproject to start.
      await tap(tester, 'mag-tab-places');
      await tap(tester, 'mag-place-${city.id}');
      expect(find.byKey(const ValueKey('mag-megapolis-badge')), findsOneWidget);
      await tap(tester, 'mag-mega-start-bridge');
      final site = w.siteOf('bridge');
      expect(site, isNotNull);
      expect(find.byKey(const ValueKey('mag-mega-sheet')), findsOneWidget);
      await closeSheet(tester);
      await closeSheet(tester);
      // The site on the map opens its sheet too.
      s.centerOn(site!.centerX, site.centerY);
      await tester.pump();
      await tester.tapAt(at(tester, s, site.x + 1, site.y + 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('mag-mega-sheet')), findsOneWidget);
      await settle(tester);
    },
  );

  testWidgets('S11: passengers and prices in a sheet, a bus in the shop', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world
      ..money = 100000
      ..xp = MagWorldProgress.xpFor(4)
      ..techs.add('combustion');
    final v = w.settlements.firstWhere((t) => t.name == 'Луговое');
    v.town!.glut[MagCargo.planks] = 200;
    s.changed();
    await tap(tester, 'mag-tab-places');
    await tap(tester, 'mag-place-${v.id}');
    expect(find.byKey(const ValueKey('mag-town-passengers')), findsOneWidget);
    expect(find.textContaining('затоварено'), findsOneWidget);
    expect(find.textContaining('дефицит'), findsWidgets);
    await closeSheet(tester);
    await tap(tester, 'mag-tab-fleet');
    await tap(tester, 'mag-buy-bus');
    expect(w.vehicles.values.last.spec.passengers, isTrue);
    await settle(tester);
  });

  testWidgets('P1: build groups, filters, removal by taps with a refund', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world..money = 100000;
    final f = w.map.startFarm, p = w.map.startPlant;
    final plan = w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt);
    expect(w.buildRoad(plan), isNull);
    s.changed();
    s.camera.zoom = 1;
    s.centerOn((f.centerX + p.centerX) / 2, (f.centerY + p.centerY) / 2 + 1);
    await tester.pump();
    // Groups: roads first; the rail group is locked; buildings and removal.
    await tap(tester, 'mag-tab-build');
    expect(find.byKey(const ValueKey('mag-road-dirt')), findsOneWidget);
    await tap(tester, 'mag-cat-rail');
    expect(s.tool, MagTool.road);
    await tap(tester, 'mag-cat-buildings');
    expect(find.byKey(const ValueKey('mag-tool-industry')), findsOneWidget);
    expect(find.byKey(const ValueKey('mag-road-dirt')), findsNothing);
    await tap(tester, 'mag-cat-remove');
    expect(s.tool, MagTool.remove);
    // Two taps in line mark the whole stretch; the bar shows the refund.
    var i = 0;
    while (!List.generate(
      4,
      (k) =>
          w.cy(plan.cells[i + k]) == w.cy(plan.cells[i]) &&
          w.cx(plan.cells[i + k]) == w.cx(plan.cells[i]) + k,
    ).every((e) => e)) {
      i++;
    }
    final a = plan.cells[i], b = plan.cells[i + 3];
    await tester.tapAt(at(tester, s, w.cx(a), w.cy(a)));
    await tester.pump();
    await tester.tapAt(at(tester, s, w.cx(b), w.cy(b)));
    await tester.pump();
    expect(s.pendingRemove.length, 4);
    final refund = w.demolishRefund(s.pendingRemove);
    expect(find.textContaining('вернётся'), findsOneWidget);
    final money = w.money;
    await tap(tester, 'mag-confirm-build');
    expect(w.money, money + refund);
    await tap(tester, 'mag-tab-build'); // back to looking
    // The fleet by kind; the places by kind.
    await tap(tester, 'mag-tab-fleet');
    await tap(tester, 'mag-fleet-kind-3');
    expect(find.byKey(const ValueKey('mag-shop-bus')), findsOneWidget);
    expect(find.byKey(const ValueKey('mag-shop-cart')), findsNothing);
    await tap(tester, 'mag-fleet-kind-0');
    await closeSheet(tester);
    await tap(tester, 'mag-tab-places');
    await tap(tester, 'mag-place-kind-1');
    expect(find.byKey(ValueKey('mag-place-${f.id}')), findsNothing);
    await tap(tester, 'mag-place-kind-0');
    await closeSheet(tester);
    await settle(tester);
  });

  testWidgets('S12: the tutorial points the way and can be turned off', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world;
    final f = w.map.startFarm, p = w.map.startPlant;
    expect(s.guideKey, 'mag-tab-build');
    await tap(tester, 'mag-tab-build');
    expect(s.overlay.guide, containsAll([f.id, p.id]));
    s.camera.zoom = 1;
    s.centerOn((f.centerX + p.centerX) / 2, (f.centerY + p.centerY) / 2 + 1);
    await tester.pump();
    await tester.tapAt(at(tester, s, f.x + f.size, f.y));
    await tester.pump();
    await tester.tapAt(at(tester, s, p.x - 1, p.y));
    await tester.pump();
    expect(s.guideKey, 'mag-confirm-build');
    await tap(tester, 'mag-confirm-build');
    await tap(tester, 'mag-tab-build');
    expect(s.guideKey, 'mag-tab-routes');
    // Off in the settings: nothing pulses.
    await tap(tester, 'mag-settings');
    await tap(tester, 'mag-tutorial');
    expect(w.tutorial, isFalse);
    expect(s.guideKey, isNull);
    await closeSheet(tester);
    await settle(tester);
  });

  testWidgets('S12: a new route — search, groups and suggestions', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world;
    final saw = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.sawmill,
    );
    await tap(tester, 'mag-tab-routes');
    await tap(tester, 'mag-new-route');
    // Search by name narrows the list to the sawmill.
    await tester.enterText(
      find.byKey(const ValueKey('mag-route-search')),
      saw.name,
    );
    await tester.pump();
    expect(find.byKey(ValueKey('mag-stop-${saw.id}')), findsOneWidget);
    expect(
      find.byKey(ValueKey('mag-stop-${w.map.startFarm.id}')),
      findsNothing,
    );
    await tap(tester, 'mag-stop-${saw.id}');
    await tester.enterText(find.byKey(const ValueKey('mag-route-search')), '');
    await tester.pump();
    // Suggestions: places that take its wood, connected ones first.
    final dest = routeDestinations(w, saw);
    expect(dest, isNotEmpty);
    expect(dest.every((e) => e.$2.contains(MagCargo.wood)), isTrue);
    expect(
      find.byKey(ValueKey('mag-suggest-${dest.first.$1.id}')),
      findsOneWidget,
    );
    await tap(tester, 'mag-suggest-${dest.first.$1.id}');
    expect(find.textContaining('Повезут'), findsOneWidget);
    // A group filter: settlements only.
    await tap(tester, 'mag-route-kind-1');
    expect(find.byKey(ValueKey('mag-stop-${saw.id}')), findsNothing);
    await tap(tester, 'mag-create-route');
    expect(w.routes.values.last.stops, [saw.id, dest.first.$1.id]);
    await closeSheet(tester);
    await settle(tester);
  });
}
