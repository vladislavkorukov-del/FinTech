import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
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

  testWidgets('S17: bodies in the shop, a hull, a terminal, a scenario', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(8)
      ..techs.addAll(['combustion', 'stud', 'shipping']);
    w.speed = 0;
    s.changed();
    // Special bodies and comfort in the shop.
    await tap(tester, 'mag-tab-fleet');
    await tap(tester, 'mag-fleet-kind-2');
    expect(find.byKey(const ValueKey('mag-shop-body-reefer')), findsOneWidget);
    expect(find.textContaining('только нефть'), findsOneWidget);
    await tap(tester, 'mag-fleet-kind-5');
    await tap(tester, 'mag-buy-barge');
    await tap(tester, 'mag-fleet-kind-0');
    final barge = w.vehicles.values.last;
    await tap(tester, 'mag-truck-${barge.id}');
    await tap(tester, 'mag-hull');
    expect(barge.hull, 1);
    await closeSheet(tester);
    // A terminal by a settlement from the road sheet.
    final v = w.settlements.first;
    int? edge;
    for (var y = v.top - 1; y <= v.bottom + 1 && edge == null; y++) {
      for (var x = v.left - 1; x <= v.right + 1; x++) {
        if (!w.map.roadable(x, y) || v.covers(x, y)) continue;
        final c = w.cellOf(x, y);
        if (w.townsBeside(c).contains(v) && w.map.industryAt(x, y) == null) {
          edge = c;
          break;
        }
      }
    }
    w.roads[edge!] = MagRoad.dirt.index;
    w.roadVersion++;
    s.changed();
    s.camera.zoom = 1.4;
    s.centerOn(w.cx(edge) + .5, w.cy(edge) + .5);
    await tester.pump();
    await tester.tapAt(at(tester, s, w.cx(edge), w.cy(edge)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tap(tester, 'mag-terminal-build-${v.id}');
    expect(w.terminals[edge], v.id);
    await closeSheet(tester);
    // A new company with a scenario.
    await tap(tester, 'mag-settings');
    await tap(tester, 'mag-new-game');
    await tap(tester, 'mag-scenario-rich');
    await settle(tester);
    expect(s.world.scenario, MagScenario.rich);
    expect(s.world.money, 30000);
    await settle(tester);
  });

  testWidgets('S18: messages in the build panel, a region, paint, auction', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(6);
    w.speed = 0;
    s.changed();
    // A new company opens regions as it grows.
    expect(w.regionsLocked, isTrue);
    final f = w.map.startFarm, p = w.map.startPlant;
    // Building: a message goes to the panel's line, not over the map.
    s.camera.zoom = 1;
    s.centerOn((f.centerX + p.centerX) / 2, (f.centerY + p.centerY) / 2);
    await tester.pump();
    await tap(tester, 'mag-tab-build');
    await tester.tapAt(at(tester, s, f.x + f.size, f.y));
    await tester.pump();
    await tester.tapAt(at(tester, s, p.x - 1, p.y));
    await tester.pump();
    final end = s.pendingRoad!.cells.last;
    await tester.tapAt(at(tester, s, w.cx(end), w.cy(end)));
    await tester.pump();
    expect(s.message, isNotNull);
    expect(find.byKey(const ValueKey('mag-message')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('mag-build-hint'))).data,
      s.message,
    );
    await tap(tester, 'mag-cancel');
    await tap(tester, 'mag-tab-build');
    // A closed region: a tap offers to open it.
    final home = w.regionOf(f.x, f.y);
    final r = home == 4 ? 3 : 4;
    final size = (w.size / 3).ceil();
    final cx = (r % 3) * size + size ~/ 2, cy = (r ~/ 3) * size + size ~/ 2;
    s.camera.zoom = 1;
    s.centerOn(cx + .5, cy + .5);
    await tester.pump();
    await tester.tapAt(at(tester, s, cx, cy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tap(tester, 'mag-region-open');
    expect(w.openRegions, contains(r));
    // Paint a vehicle.
    final v = w.vehicles.values.first;
    await tap(tester, 'mag-tab-fleet');
    await tap(tester, 'mag-truck-${v.id}');
    await tap(tester, 'mag-paint-1');
    expect(v.paint, isNotNull);
    await closeSheet(tester);
    // An auction lot in the investments tab.
    final lot = w.map.industries.firstWhere((i) => !i.owned && w.forSale(i));
    w.auction = MagAuction(lot.id, 1000, w.tick + 5 * MagRules.ticksPerDay);
    s.changed();
    await tap(tester, 'mag-balance');
    await tap(tester, 'mag-fin-tab-6');
    await tap(tester, 'mag-auction-buy');
    expect(lot.owned, isTrue);
    await closeSheet(tester);
    await settle(tester);
  });

  testWidgets('S19: a line by taps on the map; rivals; the collection', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world..money = 1000000;
    w.speed = 0;
    s.changed();
    final f = w.map.startFarm, p = w.map.startPlant;
    final routes = w.routes.length;
    await tap(tester, 'mag-tab-routes');
    await tap(tester, 'mag-new-route');
    expect(s.tool, MagTool.route);
    expect(find.byKey(const ValueKey('mag-route-bar')), findsOneWidget);
    s.camera.zoom = 1;
    s.centerOn((f.centerX + p.centerX) / 2, (f.centerY + p.centerY) / 2);
    await tester.pump();
    await tester.tapAt(at(tester, s, f.x, f.y));
    await tester.pump();
    expect(s.routeDraft.stops, [f.id]);
    // The next good stops are pointed at.
    expect(s.overlay.guide, contains(p.id));
    // A tap on the last stop takes it back; again — it returns.
    await tester.tapAt(at(tester, s, f.x, f.y));
    await tester.pump();
    expect(s.routeDraft.stops, isEmpty);
    await tester.tapAt(at(tester, s, f.x, f.y));
    await tester.pump();
    s.centerOn(p.centerX, p.centerY - 3);
    await tester.pump();
    await tester.tapAt(at(tester, s, p.x, p.y));
    await tester.pump();
    expect(s.routeDraft.stops, [f.id, p.id]);
    expect(find.byKey(const ValueKey('mag-draft-stop-1')), findsOneWidget);
    await tap(tester, 'mag-route-map-create');
    expect(w.routes.length, routes + 1);
    expect(s.tool, MagTool.view);
    await closeSheet(tester);
    // Rivals and the collection in the company sheet.
    w.xp = MagWorldProgress.xpFor(MagRules.rivalLevel);
    w.step(MagRules.ticksPerDay * MagRules.rivalEvery);
    s.changed();
    await tester.pump();
    await tap(tester, 'mag-level');
    await tap(tester, 'mag-company-tab-3');
    expect(find.byKey(const ValueKey('mag-rival-0')), findsOneWidget);
    await tap(tester, 'mag-rival-buy-0');
    expect(w.rivals.length, 1);
    await tap(tester, 'mag-company-tab-4');
    expect(find.byKey(const ValueKey('mag-collection-cart')), findsOneWidget);
    await closeSheet(tester);
    await settle(tester);
  });

  testWidgets('S23: the exchange, a broken road and its repair', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world..money = 1000000;
    w.speed = 0;
    s.changed();
    await tap(tester, 'mag-level');
    await tap(tester, 'mag-company-tab-6');
    expect(find.byKey(const ValueKey('mag-share-price')), findsOneWidget);
    await tap(tester, 'mag-shares-issue');
    expect(w.ownShares, 900);
    await closeSheet(tester);
    // A broken road cell: its sheet offers the repair.
    final f = w.map.startFarm, p = w.map.startPlant;
    final plan = w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt);
    w.buildRoad(plan);
    final c = plan.cells[plan.cells.length ~/ 2];
    w.damaged[c] = w.tick + 5 * MagRules.ticksPerDay;
    w.roadVersion++;
    s.changed();
    s.camera.zoom = 1.4;
    s.centerOn(w.cx(c) + .5, w.cy(c) + .5);
    await tester.pump();
    await tester.tapAt(at(tester, s, w.cx(c), w.cy(c)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('mag-road-damaged')), findsOneWidget);
    await tap(tester, 'mag-road-repair');
    expect(w.damaged, isEmpty);
    await closeSheet(tester);
    await settle(tester);
  });
}
