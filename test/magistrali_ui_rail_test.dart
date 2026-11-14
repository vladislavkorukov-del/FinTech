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
    await tap(tester, 'mag-tool-rail');
    expect(s.tool, MagTool.rail);
    final g = await tester.startGesture(at(tester, s, w.cx(a), w.cy(a)));
    for (var k = 1; k <= 8; k++) {
      final x = w.cx(a) + (w.cx(b) - w.cx(a)) * k / 8;
      final y = w.cy(a) + (w.cy(b) - w.cy(a)) * k / 8;
      await g.moveTo(at(tester, s, x.round(), y.round()));
      await tester.pump();
    }
    await g.up();
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
}
