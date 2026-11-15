import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/world/magistrali/mag_icons.dart';
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

  testWidgets('S13: stop orders in a new line, road load, workers', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world..money = 100000;
    final f = w.map.startFarm, p = w.map.startPlant;
    final plan = w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt);
    expect(w.buildRoad(plan), isNull);
    s.changed();
    // A new line: farm, plant; the plant keeps the load (an order).
    await tap(tester, 'mag-tab-routes');
    await tap(tester, 'mag-new-route-list');
    await tester.enterText(
      find.byKey(const ValueKey('mag-route-search')),
      f.name,
    );
    await tester.pump();
    await tap(tester, 'mag-stop-${f.id}');
    await tester.enterText(find.byKey(const ValueKey('mag-route-search')), '');
    await tester.pump();
    await tap(tester, 'mag-suggest-${p.id}');
    expect(find.textContaining('забрать зерно'), findsOneWidget);
    expect(find.textContaining('выгрузить зерно'), findsOneWidget);
    await tap(tester, 'mag-route-stop-0');
    await tap(tester, 'mag-order-nopick');
    await tap(tester, 'mag-order-save');
    expect(find.textContaining('проезд'), findsWidgets);
    await tap(tester, 'mag-create-route');
    final r = w.routes.values.last;
    expect(r.noPick, {0});
    // The order is changed from the line's card.
    await tap(tester, 'mag-route-${r.id}-stop-0');
    await tap(tester, 'mag-order-auto');
    await tap(tester, 'mag-order-save');
    expect(r.noPick, isEmpty);
    await closeSheet(tester);
    // Road load: the toggle over the map and the numbers in the road sheet.
    final mid = plan.cells[plan.cells.length ~/ 2];
    w.speed = 0; // paused: the day (and its traffic) stays
    for (final c in plan.cells) {
      w.traffic[c] = 60;
    }
    await tap(tester, 'mag-tab-build');
    await tap(tester, 'mag-traffic');
    expect(s.overlay.traffic, isTrue);
    await tester.pump();
    await tap(tester, 'mag-tab-build');
    s.camera.zoom = 1.2;
    s.centerOn(w.cx(mid) + .5, w.cy(mid) + .5);
    await tester.pump();
    await tester.tapAt(at(tester, s, w.cx(mid), w.cy(mid)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('машин в день'), findsOneWidget);
    expect(find.byKey(const ValueKey('mag-road-jam')), findsOneWidget);
    await closeSheet(tester);
    // Workers in a business sheet.
    p.staff = 4;
    await tap(tester, 'mag-tab-places');
    await tap(tester, 'mag-place-kind-3');
    await tap(tester, 'mag-place-${p.id}');
    expect(find.byKey(const ValueKey('mag-staff')), findsOneWidget);
    expect(find.textContaining('выработка +'), findsOneWidget);
    await closeSheet(tester);
    await settle(tester);
  });

  testWidgets('S14: copy and reverse a line, priority, the planner', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world
      ..money = 100000
      ..xp = MagWorldProgress.xpFor(5)
      ..techs.add('combustion');
    final f = w.map.startFarm, p = w.map.startPlant;
    w.buildRoad(w.planRoad(f.x + f.size, f.y, p.x - 1, p.y, MagRoad.dirt));
    w.createRoute([f.id, p.id]);
    final r = w.routes.values.single;
    w.assign(w.vehicles.values.single.id, r.id);
    w.step(MagRules.ticksPerDay * 10);
    w.speed = 0;
    s.changed();
    await tap(tester, 'mag-tab-routes');
    await tap(tester, 'mag-route-copy-${r.id}');
    expect(w.routes.length, 2);
    await tap(tester, 'mag-route-reverse-${r.id}');
    expect(w.routes.values.last.stops, [p.id, f.id]);
    await tap(tester, 'mag-route-priority-${r.id}');
    await tap(tester, 'mag-priority-grain');
    await tap(tester, 'mag-priority-save');
    expect(r.priority, [MagCargo.grain]);
    expect(find.textContaining('Приоритет: зерно'), findsOneWidget);
    await closeSheet(tester);
    // The planner: another vehicle on the line, bought from the card.
    await tap(tester, 'mag-balance');
    await tap(tester, 'mag-fin-tab-6');
    expect(find.byKey(const ValueKey('mag-invest-0')), findsOneWidget);
    expect(find.textContaining('Окупаемость'), findsWidgets);
    final idea = w.investmentIdeas.indexWhere(
      (i) => i.kind == MagInvestmentKind.vehicle,
    );
    expect(idea, isNonNegative);
    final before = w.vehicles.length;
    await tap(tester, 'mag-invest-go-$idea');
    expect(w.vehicles.length, before + 1);
    expect(w.vehicles.values.last.routeId, r.id);
    await closeSheet(tester);
    await settle(tester);
  });

  testWidgets('S21: icons, a city subsidy, sound settings', (tester) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world..money = 1000000;
    w.speed = 0;
    final f = w.map.startFarm, p = w.map.startPlant;
    w.subsidies.add(
      MagSubsidy(
        f.id,
        p.id,
        MagCargo.grain,
        w.tick + 10 * MagRules.ticksPerDay,
      ),
    );
    s.changed();
    await tap(tester, 'mag-tab-contracts');
    expect(find.byKey(ValueKey('mag-subsidy-${f.id}-${p.id}')), findsOneWidget);
    expect(find.byType(MagCargoIcon), findsWidgets);
    final routes = w.routes.length;
    await tap(tester, 'mag-subsidy-route-${f.id}-${p.id}');
    expect(w.routes.length, routes + 1);
    await tap(tester, 'mag-tab-fleet');
    expect(find.byType(MagVehicleIcon), findsWidgets);
    await closeSheet(tester);
    await tap(tester, 'mag-settings');
    await tap(tester, 'mag-music');
    expect(w.musicOn, isFalse);
    await tap(tester, 'mag-sound');
    expect(w.soundOn, isFalse);
    await closeSheet(tester);
    await settle(tester);
  });
}
