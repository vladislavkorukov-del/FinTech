import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finorio/finorio.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/world/finora_world_screen.dart';
import 'package:finora/presentation/screens/world/finorio/finorio_screen.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/finorio_store.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Finorio on screen: opening it from the world, building with taps, a
/// drag that never builds, pinch zoom, a real working line, saving and
/// loading, pausing in the background, and rewards paid once.
void main() {
  sqfliteFfiInit();
  late Directory dir;
  late FinanceRepository repo;
  late FinanceController c;
  setUp(() async {
    await initializeDateFormatting('ru');
    dir = await Directory.systemTemp.createTemp('finorio-ui-');
    FinorioStore.debugRoot = dir;
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
    FinorioStore.debugRoot = null;
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

  Future<FinorioScreenState> ready(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      final s = tester.stateList<FinorioScreenState>(
        find.byType(FinorioScreen),
      );
      if (s.isNotEmpty && s.first.world != null) return s.first;
    }
    fail('Finorio did not open');
  }

  /// The screen point of a cell's centre.
  Offset at(WidgetTester tester, FinorioScreenState s, int x, int y) {
    final size = tester.getSize(find.byKey(const ValueKey('finorio-map')));
    final scale = 44.0 * s.zoom;
    return Offset(
      size.width / 2 + (x + .5 - s.cameraX) * scale,
      size.height / 2 + (y + .5 - s.cameraY) * scale,
    );
  }

  (int, int) deposit(FinWorld w, FinTerrain t) {
    final cx = w.terrain.startX, cy = w.terrain.startY;
    for (var r = 0; r < 16; r++) {
      for (var y = cy - r; y <= cy + r; y++) {
        for (var x = cx - r; x <= cx + r; x++) {
          if (w.terrain.at(x, y) == t && w.machineAt(x, y) == null) {
            return (x, y);
          }
        }
      }
    }
    throw StateError('no $t');
  }

  testWidgets('opens from the world\'s games', (tester) async {
    await mount(tester, const FinoraWorldScreen());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('world-destination-5')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('world-game-flow')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('world-game-finorio')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final s = await ready(tester);
    expect(find.byKey(const ValueKey('finorio-map')), findsOneWidget);
    expect(find.textContaining('Задача 1'), findsOneWidget);
    expect(
      s.world!.kits[FinBuilding.drill],
      FinConfig.starterBuildings[FinBuilding.drill],
    );
    await tester.tap(find.byKey(const ValueKey('finorio-back')));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(FinorioScreen), findsNothing);
    expect(File('${dir.path}/finorio/world.json').existsSync(), isTrue);
  });

  testWidgets('a finger draws belts; a tap turns a building', (tester) async {
    await mount(tester, const FinorioScreen(seed: 42));
    final s = await ready(tester);
    final w = s.world!;
    // A free row of five cells near the start.
    late int bx, by;
    search:
    for (var r = 0; r < 16; r++) {
      for (var y = w.terrain.startY - r; y <= w.terrain.startY + r; y++) {
        for (var x = w.terrain.startX - r; x <= w.terrain.startX + r; x++) {
          if ([
            for (var k = 0; k < 6; k++) w.whyNot(FinBuilding.belt, x + k, y),
          ].every((e) => e == null)) {
            bx = x;
            by = y;
            break search;
          }
        }
      }
    }
    s.centerOn(bx + 2, by);
    await tester.pump();
    final tile = find.byKey(const ValueKey('finorio-build-belt'));
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    final g = await tester.startGesture(at(tester, s, bx, by));
    for (var k = 1; k <= 4; k++) {
      await g.moveTo(at(tester, s, bx + k, by));
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    for (var k = 0; k <= 4; k++) {
      expect(w.machineAt(bx + k, by)?.isBelt, isTrue, reason: 'cell $k');
      expect(w.machineAt(bx + k, by)?.dir, 1); // right
    }
    // A store at the line's end.
    final store = find.byKey(const ValueKey('finorio-build-storage'));
    await tester.ensureVisible(store);
    await tester.pump();
    await tester.tap(store);
    await tester.pump();
    await tester.tapAt(at(tester, s, bx + 5, by));
    await tester.pump();
    final m = w.machineAt(bx + 5, by)!;
    final before = m.dir;
    // Tapping it again with the tool still chosen turns it.
    await tester.tapAt(at(tester, s, bx + 5, by));
    await tester.pump();
    expect(m.dir, (before + 1) % 4);
  });

  testWidgets('build with taps, never by dragging; a powered line runs', (
    tester,
  ) async {
    await mount(tester, const FinorioScreen(seed: 42));
    final s = await ready(tester);
    final w = s.world!;
    expect(w.machines, isEmpty);
    final (ix, iy) = deposit(w, FinTerrain.iron);
    s.centerOn(ix, iy);
    await tester.pump();
    Future<void> choose(String key) async {
      final tile = find.byKey(ValueKey(key));
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
    }

    Future<void> tapCell(int x, int y) async {
      await tester.tapAt(at(tester, s, x, y));
      await tester.pump(const Duration(milliseconds: 50));
    }

    // A drag with a building chosen moves the map and builds nothing.
    await choose('finorio-build-drill');
    await tester.dragFrom(at(tester, s, ix, iy), const Offset(-90, 40));
    await tester.pump();
    expect(w.machines, isEmpty);
    // Pinch zooms out.
    final f1 = await tester.startGesture(const Offset(140, 400));
    final f2 = await tester.startGesture(const Offset(250, 400), pointer: 7);
    await f1.moveTo(const Offset(180, 400));
    await f2.moveTo(const Offset(210, 400));
    await f1.up();
    await f2.up();
    await tester.pump();
    expect(s.zoom, lessThan(1));
    s.centerOn(ix, iy);
    await tester.pump();

    // Real taps on cells build: drill (facing right), generator.
    await tapCell(ix, iy);
    expect(w.machineAt(ix, iy)?.kind, FinBuilding.drill);
    await choose('finorio-build-generator');
    var gy = iy + 2;
    while (w.whyNot(FinBuilding.generator, ix, gy) != null) {
      gy++;
    }
    await tapCell(ix, gy);
    final gen = w.machineAt(ix, gy)!;
    // Fuel it from its inspector.
    await tester.tap(find.byKey(const ValueKey('finorio-tool-select')));
    await tester.pump();
    await tapCell(gen.x, gen.y);
    // Quick actions float above it; the full panel opens from there.
    expect(find.byKey(ValueKey('finorio-quick-${gen.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('finorio-inspector-${gen.id}')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('finorio-quick-info')));
    await tester.pump();
    expect(find.byKey(ValueKey('finorio-inspector-${gen.id}')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('finorio-fuel')));
    await tester.pump();
    expect(gen.input[FinItem.biomass], 10);
    await tester.tap(find.byKey(const ValueKey('finorio-inspector-close')));
    await tester.pump();
    // A belt line by two taps, then a store at its end.
    var end = ix + 1;
    while (end < ix + 4 &&
        w.whyNot(FinBuilding.belt, end + 1, iy) == null &&
        w.whyNot(FinBuilding.storage, end + 2, iy) == null) {
      end++;
    }
    // Keep the whole line on screen.
    s.centerOn(ix + 2, iy);
    await tester.pump();
    await choose('finorio-build-belt');
    await tapCell(ix + 1, iy);
    await tapCell(end, iy);
    expect(w.machineAt(ix + 1, iy)?.isBelt, isTrue);
    expect(w.machineAt(end, iy)?.isBelt, isTrue);
    await choose('finorio-build-storage');
    await tapCell(end + 1, iy);
    final store = w.machineAt(end + 1, iy);
    expect(store?.kind, FinBuilding.storage);
    // The fixed step runs: ore is mined, carried and stored.
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(w.created[FinItem.ironOre], greaterThan(3));
    expect(store!.input[FinItem.ironOre], greaterThan(0));
    expect(w.tasksDone, containsAll([1, 2, 3]));
    // Inspecting the drill shows its state and speed.
    await tester.tap(find.byKey(const ValueKey('finorio-tool-select')));
    await tester.pump();
    await tapCell(ix, iy);
    await tester.tap(find.byKey(const ValueKey('finorio-quick-info')));
    await tester.pump();
    expect(find.text('Работает'), findsOneWidget);
    expect(find.textContaining('/ мин'), findsOneWidget);

    // In the background nothing moves.
    final tick = w.tick;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(w.tick, tick);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(w.tick, greaterThan(tick));

    // Saved and loaded: the same factory comes back.
    await tester.runAsync(s.save);
    final saved = w.machines.length;
    await tester.pumpWidget(Container());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await mount(tester, const FinorioScreen(seed: 1));
    final again = await ready(tester);
    expect(again.world!.seed, 42);
    expect(again.world!.machines, hasLength(saved));
    expect(again.world!.tasksDone, containsAll([1, 2, 3]));
    await tester.pumpWidget(Container());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });

  test('rewards are paid once, also after loading the save again', () async {
    final w = FinWorld.start(5)..tasksDone.addAll([1, 2, 3]);
    final before = c.data.world.sparks;
    await c.claimFinorioRewards(w.earnedRewards);
    final once = c.data.world.sparks;
    expect(once - before, 3 * 15);
    await c.claimFinorioRewards(w.earnedRewards);
    // A reloaded save claims the same ids again: nothing is added.
    final again = finWorldFromJson(w.toJson());
    await c.claimFinorioRewards(again.earnedRewards);
    expect(c.data.world.sparks, once);
    // And the ledger reloaded from disk agrees.
    final reloaded = await repo.load();
    expect(
      reloaded.world.rewards.keys.where((k) => k.startsWith('finorio:')),
      hasLength(3),
    );
    expect(
      () => c.claimFinorioRewards(['finorio:task:11:v1']),
      throwsFormatException,
    );
  });
}
