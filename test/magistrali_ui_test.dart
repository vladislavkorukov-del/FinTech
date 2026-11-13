import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/magistrali/magistrali.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/world/finora_world_screen.dart';
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

/// «Магистрали» on screen, by real touches: open it from the world's
/// games, move and zoom the map, draw a road with a finger, buy a truck,
/// make a route, put the truck on it, watch it deliver and earn, upgrade
/// it, and come back to the same company after leaving.
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

  testWidgets('opens from the world\'s games', (tester) async {
    await mount(tester, const FinoraWorldScreen());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('world-destination-5')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('world-game-flow')), findsOneWidget);
    expect(find.byKey(const ValueKey('world-game-finorio')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('world-game-magistrali')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final s = await ready(tester);
    expect(find.byKey(const ValueKey('mag-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('mag-task-1')), findsOneWidget);
    expect(s.world.money, MagRules.startMoney);
    await tester.tap(find.byKey(const ValueKey('mag-back')));
    final file = File('${dir.path}/magistrali/world.json');
    for (
      var i = 0;
      i < 80 &&
          (!file.existsSync() ||
              find.byType(MagistraliScreen).evaluate().isNotEmpty);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(MagistraliScreen), findsNothing);
    expect(File('${dir.path}/magistrali/world.json').existsSync(), isTrue);
  });

  testWidgets('the whole first line by touch, then saved and continued', (
    tester,
  ) async {
    await mount(tester, const MagistraliScreen(seed: MagRules.defaultSeed));
    final s = await ready(tester);
    final w = s.world;
    final farm = w.map.startFarm, plant = w.map.startPlant;

    // A drag in view mode moves the map; a pinch zooms.
    final cam0 = (s.camera.x, s.camera.y);
    await tester.dragFrom(const Offset(195, 420), const Offset(-80, 30));
    await tester.pump();
    expect((s.camera.x, s.camera.y), isNot(cam0));
    final zoom = s.camera.zoom;
    final f1 = await tester.startGesture(const Offset(140, 450));
    final f2 = await tester.startGesture(const Offset(250, 450), pointer: 7);
    await f1.moveTo(const Offset(110, 450));
    await f2.moveTo(const Offset(280, 450));
    await f1.up();
    await f2.up();
    await tester.pump();
    expect(s.camera.zoom, greaterThan(zoom));
    expect(w.roads.every((r) => r == 0), isTrue);

    // Build: a finger draws the road, «Построить» builds it.
    s.camera.zoom = 1;
    s.centerOn(
      (farm.centerX + plant.centerX) / 2,
      (farm.centerY + plant.centerY) / 2 + 1,
    );
    await tap(tester, 'mag-tab-build');
    expect(find.byKey(const ValueKey('mag-road-dirt')), findsOneWidget);
    final from = (farm.x + farm.size, farm.y);
    final to = (plant.x - 1, plant.y);
    final g = await tester.startGesture(at(tester, s, from.$1, from.$2));
    for (var k = 1; k <= 8; k++) {
      final x = from.$1 + (to.$1 - from.$1) * k / 8;
      final y = from.$2 + (to.$2 - from.$2) * k / 8;
      await g.moveTo(at(tester, s, x.round(), y.round()));
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('mag-confirm')), findsOneWidget);
    expect(w.roads.every((r) => r == 0), isTrue); // not yet
    final cost = s.pendingRoad!.cost;
    await tap(tester, 'mag-confirm-build');
    expect(w.money, MagRules.startMoney - cost + 500); // + task 1 reward
    expect(w.connected(farm, plant), isTrue);
    expect(w.tasksDone, contains(1));
    await tap(tester, 'mag-tab-build'); // back to looking

    // Buy a second truck.
    await tap(tester, 'mag-tab-fleet');
    await tap(tester, 'mag-buy-pickup');
    expect(w.vehicles.length, 2);
    await closeSheet(tester);

    // A route: farm → plant, from the routes section.
    await tap(tester, 'mag-tab-routes');
    await tap(tester, 'mag-new-route');
    await tap(tester, 'mag-stop-${farm.id}');
    await tap(tester, 'mag-stop-${plant.id}');
    await tap(tester, 'mag-create-route');
    expect(w.routes.length, 1);
    final route = w.routes.values.first;
    // Two trucks onto it.
    await tap(tester, 'mag-route-add-truck-${route.id}');
    await tap(tester, 'mag-route-add-truck-${route.id}');
    expect(w.vehicles.values.every((v) => v.routeId == route.id), isTrue);
    await closeSheet(tester);

    // Watch: at 4× the trucks drive by road and deliver.
    await tap(tester, 'mag-speed-4');
    expect(w.speed, 4);
    final money = w.money;
    var sawDriving = false;
    for (var i = 0; i < 400 && w.deliveries == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      for (final v in w.vehicles.values) {
        if (v.state == MagVehicleState.driving) {
          sawDriving = true;
          expect(w.roads[v.cell], isNot(0));
        }
      }
    }
    expect(sawDriving, isTrue);
    expect(w.deliveries, greaterThan(0));
    expect(w.money, greaterThan(money));
    // The shared Finora world got its one reward.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(
      c.data.world.rewards.containsKey('magistrali:first_delivery:v1'),
      isTrue,
    );

    // Pause, then upgrade a truck from its sheet: it really gets faster.
    await tap(tester, 'mag-speed-0');
    final truck = w.vehicles.values.first;
    final speed = w.speedOf(truck);
    await tap(tester, 'mag-tab-upgrades');
    await tap(tester, 'mag-truck-${truck.id}');
    await tap(tester, 'mag-upgrade-engine');
    expect(truck.level(MagUpgrade.engine), 1);
    expect(w.speedOf(truck), greaterThan(speed));
    await closeSheet(tester);

    // A place opens its information.
    s.centerOn(plant.centerX, plant.centerY);
    await tester.pump();
    await tester.tapAt(at(tester, s, plant.x + 1, plant.y + 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(ValueKey('mag-industry-${plant.id}')), findsOneWidget);
    await closeSheet(tester);

    // Saved and loaded: the same company comes back.
    await tester.runAsync(s.save);
    final saved = (await tester.runAsync(() => MagistraliStore().load()))!;
    expect(saved.money, w.money);
    expect(saved.deliveries, w.deliveries);
    expect(saved.vehicles.length, 2);
    expect(saved.routes.length, 1);
    expect(saved.vehicles.values.first.level(MagUpgrade.engine), 1);
    expect(saved.connected(farm, plant), isTrue);
  });
}
