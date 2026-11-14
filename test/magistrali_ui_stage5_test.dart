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

/// Master plan stage 5 on screen, by real touches: drawing roads without
/// stray taps spoiling them, carrying a road on from its end, tapping a
/// road to lay a better surface, enlarging a warehouse, building the new
/// industry, and the finance centre.
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

  testWidgets('roads: no stray roads, carried on, tapped to upgrade', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world..money = 100000;
    final farm = w.map.startFarm, plant = w.map.startPlant;
    s.camera.zoom = 1;
    s.centerOn(
      (farm.centerX + plant.centerX) / 2,
      (farm.centerY + plant.centerY) / 2 + 1,
    );
    await tap(tester, 'mag-tab-build');
    final from = (farm.x + farm.size, farm.y);
    final to = (plant.x - 1, plant.y);
    final mid = ((from.$1 + to.$1) ~/ 2, from.$2);

    // Moving the map in build mode never lays a road.
    final camX = s.camera.x;
    final p0 = at(tester, s, from.$1, from.$2);
    final g = await tester.startGesture(p0);
    for (var k = 1; k <= 6; k++) {
      await g.moveTo(p0 + Offset(-20.0 * k, 6.0 * k));
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('mag-confirm')), findsNothing);
    expect(s.pendingRoad, isNull);
    expect(s.camera.x, isNot(camX));
    s.centerOn(
      (farm.centerX + plant.centerX) / 2,
      (farm.centerY + plant.centerY) / 2 + 1,
    );
    await tester.pump();

    // Tap the start and half way: half the road is planned.
    await tester.tapAt(at(tester, s, from.$1, from.$2));
    await tester.pump();
    await tester.tapAt(at(tester, s, mid.$1, mid.$2));
    await tester.pump();
    expect(find.byKey(const ValueKey('mag-confirm')), findsOneWidget);
    final half = s.pendingRoad!.cells.length;
    // A tap on its end only reminds what to do.
    await tester.tapAt(at(tester, s, mid.$1, mid.$2));
    await tester.pump();
    expect(s.pendingRoad!.cells.length, half);
    // A further tap carries it on from its end.
    await tester.tapAt(at(tester, s, to.$1, to.$2));
    await tester.pump();
    expect(s.pendingRoad!.cells.length, greaterThan(half));
    expect(s.pendingRoad!.cells.first, w.cellOf(from.$1, from.$2));
    await tap(tester, 'mag-confirm-build');
    expect(w.connected(farm, plant), isTrue);
    await tap(tester, 'mag-tab-build'); // back to looking

    // Tap the road: its stretch and a better surface.
    w.xp = MagWorldProgress.xpFor(2);
    s.changed();
    await tester.pump();
    final cell = w.cellOf(mid.$1, mid.$2);
    expect(w.roads[cell], MagRoad.dirt.index);
    await tester.tapAt(at(tester, s, mid.$1, mid.$2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('mag-road-sheet')), findsOneWidget);
    final stretch = w.roadSegment(cell);
    await tap(tester, 'mag-road-upgrade');
    for (final c in stretch) {
      expect(w.roads[c], MagRoad.asphalt.index);
    }
    expect(w.journal.entries.last.category, 'roads');
  });

  testWidgets('a bigger warehouse, the new industry, the finance centre', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world
      ..money = 500000
      ..xp = MagWorldProgress.xpFor(3)
      ..techs.add('storage');
    s.changed();
    await tester.pump();
    final p = w.map.startPlant;
    late int wx, wy;
    search:
    for (var r = 3; r < 20; r++) {
      for (var d = -r; d <= r; d++) {
        if (w.warehouseBlocker(p.x + d, p.y + r) == null) {
          wx = p.x + d;
          wy = p.y + r;
          break search;
        }
      }
    }
    expect(w.buildWarehouse(wx, wy), isNull);
    final wh = w.warehouses.single;
    s.changed();
    await tester.pump();
    s.centerOn(wh.centerX, wh.centerY);
    await tester.pump();
    await tester.tapAt(at(tester, s, wh.x, wh.y));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tap(tester, 'mag-warehouse-upgrade');
    expect(wh.level, 2);
    await closeSheet(tester);

    // The build list shows the new industry; the steel mill waits for
    // level 4.
    await tap(tester, 'mag-tab-build');
    await tap(tester, 'mag-cat-buildings');
    await tap(tester, 'mag-tool-industry');
    expect(find.byKey(const ValueKey('mag-build-brickworks')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('mag-build-steelMill')),
    );
    final mill = tester.widget<ListTile>(
      find.byKey(const ValueKey('mag-build-steelMill')),
    );
    expect(mill.enabled, isFalse);
    await closeSheet(tester);
    await tap(tester, 'mag-tab-build');

    // The finance centre: every tab opens.
    await tap(tester, 'mag-balance');
    expect(find.byKey(const ValueKey('mag-finance-center')), findsOneWidget);
    expect(find.byKey(const ValueKey('mag-journal')), findsOneWidget);
    for (var k = 1; k < 5; k++) {
      await tap(tester, 'mag-fin-tab-$k');
      expect(tester.takeException(), isNull);
    }
    expect(find.textContaining('Склады (1)'), findsOneWidget);
  });

  testWidgets('stage 6: a city, its specialization and its order', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world;
    final v = w.settlements.firstWhere((t) => t.name == 'Луговое');
    v.town!
      ..level = 5
      ..specialization = MagSpecialization.industry;
    w.step(MagRules.ticksPerDay);
    s.changed();
    await tester.pump();
    final order = w.cityOrders.single;
    expect(order.to, v.id);
    await tap(tester, 'mag-tab-contracts');
    expect(find.text('Городские заказы'), findsOneWidget);
    await tap(tester, 'mag-city-order-${order.id}');
    expect(find.byKey(ValueKey('mag-town-${v.id}')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mag-town-specialization')),
      findsOneWidget,
    );
    expect(find.textContaining('Спрос недели'), findsOneWidget);
    await closeSheet(tester);
    // A hamlet tells what it will become.
    final hamlet = w.settlements.firstWhere((t) => t.town!.level == 1);
    await tap(tester, 'mag-tab-places');
    await tap(tester, 'mag-place-${hamlet.id}');
    expect(find.byKey(const ValueKey('mag-town-future')), findsOneWidget);
  });

  testWidgets('S7: a logistics centre and the advice tab', (tester) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world
      ..money = 500000
      ..xp = MagWorldProgress.xpFor(8)
      ..techs.addAll(['storage', 'autosupply', 'dispatch', 'logcenter']);
    final p = w.map.startPlant;
    late int cx, cy;
    search:
    for (var r = 3; r < 20; r++) {
      for (var d = -r; d <= r; d++) {
        if (w.buildBlocker(MagIndustryKind.logisticsCenter, p.x + d, p.y + r) ==
            null) {
          cx = p.x + d;
          cy = p.y + r;
          break search;
        }
      }
    }
    expect(w.buildIndustry(MagIndustryKind.logisticsCenter, cx, cy), isNull);
    final c = w.centers.single;
    s.changed();
    // Level 8 pays the world's level rewards: let the database finish.
    for (var k = 0; k < 20; k++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    s.centerOn(c.centerX, c.centerY);
    await tester.pump();
    await tester.tapAt(at(tester, s, c.x, c.y));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('mag-center-sheet')), findsOneWidget);
    expect(find.textContaining('автопарке'), findsOneWidget);
    expect(s.overlay.plan, isNotEmpty); // its reach is lit
    await tap(tester, 'mag-center-plants');
    expect(c.supplyPlants, isFalse);
    await closeSheet(tester);
    expect(s.overlay.plan, isEmpty);

    // The advice tab: the idle cart is advised; a tap opens it.
    await tap(tester, 'mag-balance');
    await tap(tester, 'mag-fin-tab-5');
    expect(find.byKey(const ValueKey('mag-advice-0')), findsOneWidget);
    final idle = w.advice.indexWhere(
      (a) => a.kind == MagAdviceKind.idleVehicle,
    );
    expect(idle, isNonNegative);
    await tap(tester, 'mag-advice-$idle');
    expect(
      find.byKey(ValueKey('mag-vehicle-${w.vehicles.keys.single}')),
      findsOneWidget,
    );
    for (var k = 0; k < 20; k++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  });
}
