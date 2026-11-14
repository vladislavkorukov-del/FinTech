import 'dart:async';
import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/world/magistrali/mag_screen.dart';
import 'package:finora/presentation/screens/world/magistrali/mag_town.dart';
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

  testWidgets('S15: achievements, chronicle, loan, route load, fleet', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world
      ..money = 100000
      ..xp = MagWorldProgress.xpFor(6)
      ..techs.add('combustion');
    final f = w.map.startFarm, p = w.map.startPlant;
    w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt));
    w.createRoute([f.id, p.id]);
    final r = w.routes.values.single;
    w.buyTruck('pickup');
    w.speed = 0;
    s.changed();
    // The company: achievements and the chronicle.
    await tap(tester, 'mag-level');
    await tap(tester, 'mag-company-tab-1');
    expect(
      find.byKey(const ValueKey('mag-achievement-roads50')),
      findsOneWidget,
    );
    await tap(tester, 'mag-company-tab-2');
    expect(find.textContaining('Открыт маршрут'), findsOneWidget);
    await tap(tester, 'mag-company-tab-0');
    await closeSheet(tester);
    // The bank.
    await tap(tester, 'mag-balance');
    await tap(tester, 'mag-fin-tab-7');
    await tap(tester, 'mag-loan-take-5000');
    expect(w.debt, 5000);
    await tap(tester, 'mag-loan-pay-all');
    expect(w.debt, 0);
    await closeSheet(tester);
    // A line: the minimum load cycles; a stop visited only when needed.
    await tap(tester, 'mag-tab-routes');
    await tap(tester, 'mag-route-minload-${r.id}');
    expect(r.minLoad, 75);
    await tap(tester, 'mag-route-${r.id}-stop-1');
    await tap(tester, 'mag-order-ifcargo');
    await tap(tester, 'mag-order-save');
    expect(r.ifCargo, {1});
    await closeSheet(tester);
    // The fleet: everyone repaired, an old one replaced.
    for (final v in w.vehicles.values) {
      v.wear = 70;
    }
    await tap(tester, 'mag-tab-fleet');
    await tap(tester, 'mag-repair-all');
    expect(w.vehicles.values.every((v) => v.wear == 0), isTrue);
    expect(find.byKey(const ValueKey('mag-replace-all')), findsOneWidget);
    await tap(tester, 'mag-replace-all');
    expect(w.vehicles.values.every((v) => w.newerModelFor(v) == null), isTrue);
    await closeSheet(tester);
    await settle(tester);
  });

  testWidgets('S16: special contracts, rich deposit, recipes, depot, merge', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world
      ..money = 1000000
      ..xp = MagWorldProgress.xpFor(8)
      ..techs.add('combustion');
    final f = w.map.startFarm, p = w.map.startPlant;
    w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt));
    w.step(MagRules.ticksPerDay);
    w.speed = 0;
    s.changed();
    // Special contracts in the contracts sheet; one given up.
    expect(w.deals, isNotEmpty);
    await tap(tester, 'mag-tab-contracts');
    final d = w.deals.first;
    expect(find.byKey(ValueKey('mag-deal-${d.id}')), findsOneWidget);
    await tap(tester, 'mag-deal-drop-${d.id}');
    expect(w.deals, isNot(contains(d)));
    await closeSheet(tester);
    // A rich deposit in its sheet.
    final rich = w.map.industries.firstWhere(w.isRich);
    await tap(tester, 'mag-tab-places');
    await tap(tester, 'mag-place-kind-2');
    await tap(tester, 'mag-place-${rich.id}');
    expect(find.byKey(const ValueKey('mag-rich')), findsOneWidget);
    await closeSheet(tester);
    // An own factory with two recipes: what to process first.
    final factory = w.map.industries.firstWhere(
      (i) => i.kind == MagIndustryKind.factory,
    );
    w.buyIndustry(factory.id);
    s.changed();
    await tap(tester, 'mag-tab-places');
    await tap(tester, 'mag-place-kind-3');
    await tap(tester, 'mag-place-${factory.id}');
    await tap(tester, 'mag-first-ore');
    expect(w.firstInput[factory.id], MagCargo.ore);
    await closeSheet(tester);
    // A depot from the road sheet.
    final cell = w.entranceOf(p)!;
    s.camera.zoom = 1.3;
    s.centerOn(w.cx(cell) + .5, w.cy(cell) + .5);
    await tester.pump();
    await tester.tapAt(at(tester, s, w.cx(cell), w.cy(cell)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tap(tester, 'mag-depot-build');
    expect(w.depots, isNotEmpty);
    await closeSheet(tester);
    // Joining orders: the switch in the orders sheet.
    await tap(tester, 'mag-tab-fleet');
    await tap(tester, 'mag-open-orders');
    await tap(tester, 'mag-auto-merge');
    expect(w.autoMerge, isFalse);
    await closeSheet(tester);
    await settle(tester);
  });

  testWidgets('S20: a big order to a small truck, growth, editor, report', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world
      ..money = 1000000
      ..techs.add('combustion');
    w.speed = 0;
    final f = w.map.startFarm, p = w.map.startPlant;
    w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt));
    w.vehicles.clear();
    w.buyTruck('pickup');
    final truck = w.vehicles.values.single;
    f.stock[MagCargo.grain] = (f.stock[MagCargo.grain] ?? 0) + 60;
    w.created[MagCargo.grain] = (w.created[MagCargo.grain] ?? 0) + 60;
    expect(
      w.createOrder(cargo: MagCargo.grain, from: f.id, to: p.id, amount: 52),
      isNull,
    );
    final o = w.orders.orders.last;
    s.changed();
    // The reported bug: a truck smaller than the order can be chosen now.
    await tap(tester, 'mag-tab-fleet');
    await tap(tester, 'mag-open-orders');
    await tap(tester, 'mag-order-assign-${o.id}');
    expect(find.textContaining('остаток — отдельным заказом'), findsOneWidget);
    await tap(tester, 'mag-order-truck-${truck.id}');
    expect(o.vehicle, truck.id);
    expect(o.amount, w.capacityOf(truck));
    expect(w.orders.orders.last.amount, 52 - w.capacityOf(truck));
    await closeSheet(tester);
    // A settlement: one growth bar and what to bring.
    final v = w.settlements.firstWhere((t) => t.town!.level == 1);
    unawaited(showTownSheet(s, v.id));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('mag-town-growth')), findsOneWidget);
    expect(find.textContaining('Привезите:'), findsOneWidget);
    expect(find.byKey(const ValueKey('mag-town-access')), findsOneWidget);
    await closeSheet(tester);
    // The map report from the settings.
    await tap(tester, 'mag-settings');
    await tap(tester, 'mag-map-report');
    expect(find.byKey(const ValueKey('mag-map-viable')), findsOneWidget);
    expect(find.byKey(const ValueKey('mag-errors-none')), findsOneWidget);
    await closeSheet(tester);
    await closeSheet(tester);
    await settle(tester);
  });
}
