import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finora_world.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/world/world_garden_album.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  test(
    'six PNG stages keep legacy growth thresholds and real full completion',
    () {
      for (final (saved, expected) in [
        (0, 0),
        (1, 1),
        (1999, 1),
        (2000, 1),
        (4000, 2),
        (6000, 2),
        (7499, 2),
        (7500, 3),
        (7999, 3),
        (8000, 4),
        (9990, 4),
        (9999, 4),
        (10000, 5),
        (12000, 5),
      ]) {
        final plant = WorldPlant.of(
          Goal(id: 'g', name: 'Цель', targetMinor: 10000, savedMinor: saved),
          [],
        );
        expect(plant.visualStage, expected, reason: 'saved=$saved');
      }
      for (final target in [0, -1]) {
        final plant = WorldPlant.of(
          Goal(id: 'g', name: 'Цель', targetMinor: target, savedMinor: 10000),
          [],
        );
        expect(plant.ratio, 0);
        expect(plant.visualStage, 0);
      }
      expect(
        WorldPlant.of(
          const Goal(
            id: 'g',
            name: 'Цель',
            targetMinor: 10000,
            savedMinor: -100,
          ),
          [],
        ).visualStage,
        0,
      );
      expect(worldGardenPercent(.9999), '99,9%');
      expect(worldGardenPercent(1), '100%');
      expect(worldGardenPercent(double.nan), '0%');
    },
  );

  test(
    'full source frame has the same pot anchor and square geometry at every stage',
    () {
      for (final size in [
        const Size(288, 360),
        const Size(708, 260),
        const Size(100, 540),
      ]) {
        final geometry = WorldGardenGeometry(size);
        final rect = geometry.spriteRect;
        expect(rect.width, closeTo(rect.height, 1e-9));
        expect(rect.left + .493 * rect.width, closeTo(size.width * .5, 1e-9));
        expect(rect.top + .965 * rect.height, closeTo(size.height * .82, 1e-9));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
      }
      for (final path in WorldGardenArt.stages) {
        final bytes = File(path).readAsBytesSync();
        expect(bytes.sublist(16, 20), [0, 0, 4, 230]); // 1254px IHDR width.
        expect(bytes.sublist(20, 24), [0, 0, 4, 230]);
        expect(bytes[25], 6, reason: '$path retains its original RGBA canvas');
      }
    },
  );

  sqfliteFfiInit();
  late Directory dir;
  late FinanceRepository repo;
  late FinanceController controller;
  setUp(() async {
    await initializeDateFormatting('ru');
    dir = await Directory.systemTemp.createTemp('finora-garden-art-');
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/db',
    );
    await repo.save(
      const FinanceData(
        accounts: [Account(id: 'a', name: 'Карта')],
        members: [Member(id: 'me', name: 'Я')],
        goals: [
          Goal(
            id: 'trip',
            name: 'Путешествие к далёкому северному сиянию',
            targetMinor: 10000,
            savedMinor: 4000,
          ),
          Goal(
            id: 'books',
            name: 'Библиотека',
            targetMinor: 10000,
            savedMinor: 9990,
          ),
        ],
      ),
    );
    controller = FinanceController(repo, _Quiet(), await repo.load());
    await controller.syncWorld();
  });
  tearDown(() async {
    controller.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(320, 640),
    double scale = 1.6,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark, 'coffee'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: const WorldGardenScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'selector persists actual goal and only one source sprite is drawn',
    (tester) async {
      await mount(tester, scale: 1);
      expect(
        find.byKey(const ValueKey('world-garden-sprite-stage-2')),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .where(
              (i) =>
                  i.image is ResizeImage &&
                  (i.image as ResizeImage).imageProvider is AssetImage &&
                  ((i.image as ResizeImage).imageProvider as AssetImage)
                      .assetName
                      .contains('/garden/stages/'),
            )
            .length,
        1,
      );
      await tester.tap(
        find.byKey(const ValueKey('world-garden-goal-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Библиотека').last);
      for (
        var i = 0;
        i < 80 && controller.data.world.gardenGoalId != 'books';
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(controller.data.world.gardenGoalId, 'books');
      expect(
        find.byKey(const ValueKey('world-garden-sprite-stage-4')),
        findsOneWidget,
      );
      final saved = await tester.runAsync(repo.load);
      expect(saved!.world.gardenGoalId, 'books');
      expect(
        saved.goals.last.savedMinor,
        9990,
        reason: 'UI only selects; it never creates savings',
      );
      expect(find.text('99,9% накоплено'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        controller.dispose();
        await repo.close();
        repo = await FinanceRepository.open(
          factory: databaseFactoryFfi,
          path: '${dir.path}/db',
        );
        controller = FinanceController(repo, _Quiet(), await repo.load());
      });
      await mount(tester, scale: 1);
      expect(controller.data.world.gardenGoalId, 'books');
      expect(
        find.byKey(const ValueKey('world-garden-sprite-stage-4')),
        findsOneWidget,
      );
      await tester.runAsync(() => controller.deleteGoal('books'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('world-garden-sprite-stage-2')),
        findsOneWidget,
      );
      expect(controller.data.world.gardenGoalId, 'trip');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all stages share the same rectangle in portrait and landscape with large text',
    (tester) async {
      for (final size in [const Size(320, 640), const Size(740, 360)]) {
        await mount(tester, size: size);
        Rect? reference;
        for (final saved in [0, 1000, 4000, 7500, 8000, 10000]) {
          await tester.runAsync(
            () => controller.saveGoal(
              controller.goal('trip')!.copyWith(savedMinor: saved),
            ),
          );
          await tester.pumpAndSettle();
          final stage = WorldPlant.of(
            controller.goal('trip')!,
            controller.data.entries,
          ).visualStage;
          final sprite = find.byKey(
            ValueKey('world-garden-sprite-stage-$stage'),
          );
          expect(sprite, findsOneWidget);
          final rect = tester.getRect(sprite);
          reference ??= rect;
          expect(rect, reference);
          expect(tester.widget<Image>(sprite).fit, BoxFit.contain);
          expect(
            tester
                .widget<Image>(
                  find.byKey(const ValueKey('world-garden-background')),
                )
                .fit,
            BoxFit.cover,
          );
          expect(tester.takeException(), isNull, reason: '$size stage$stage');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'no goals has honest creation action and no financial or plant substitute',
    (tester) async {
      await tester.runAsync(
        () => controller.mutate((d) => d.copyWith(goals: [])),
      );
      await mount(tester);
      expect(find.byType(WorldGardenScene), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('world-garden-create-goal')),
        180,
        maxScrolls: 20,
      );
      expect(find.text('Создать цель'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
