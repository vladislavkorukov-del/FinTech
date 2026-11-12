import 'dart:io';
import 'dart:ui' as ui;

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finora_world.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/wardrobe.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/world/finora_world_screen.dart';
import 'package:finora/presentation/screens/world/world_art.dart';
import 'package:finora/presentation/screens/world/flow_screens.dart';
import 'package:finora/presentation/screens/world/world_collections.dart';
import 'package:finora/presentation/screens/world/world_customization.dart';
import 'package:finora/presentation/screens/world/world_garden_album.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/screenshot_fonts.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  testWidgets(
    'world renders actual scene, plants, catalog, collections and album',
    (tester) async {
      sqfliteFfiInit();
      if (Platform.environment.containsKey('FINORA_WORLD_CAPTURE_DIR')) {
        await tester.runAsync(loadScreenshotFonts);
      }
      await initializeDateFormatting('ru');
      final now = DateTime(2026, 11, 8, 12);
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('finora-world-shots-'),
      );
      final repo = await tester.runAsync(
        () => FinanceRepository.open(
          factory: databaseFactoryFfi,
          path: '${dir!.path}/db',
        ),
      );
      var world = const WorldState();
      for (final id in [
        'first_goal',
        'first_payment',
        'categorized',
        'tutorial',
      ]) {
        world = WorldEngine.reward(world, id, now: now);
      }
      for (final id in ['crystal', 'tea']) {
        world = WorldEngine.purchase(world, id, points: 150);
      }
      world = WorldEngine.configure(
        world,
        background: 'mint',
        decor: {'left': 'crystal', 'shelf': 'tea'},
        now: now,
      );
      await tester.runAsync(
        () => repo!.save(
          FinanceData(
            accounts: const [Account(id: 'a', name: 'Основная карта')],
            members: const [Member(id: 'me', name: 'Я')],
            goals: const [
              Goal(
                id: 'garden',
                name: 'Путешествие',
                targetMinor: 100000,
                savedMinor: 65000,
                color: 0xFF9DE5C7,
              ),
              Goal(
                id: 'books',
                name: 'Домашняя библиотека',
                targetMinor: 40000,
                savedMinor: 40000,
                color: 0xFFE5C894,
              ),
              Goal(
                id: 'cozy',
                name: 'Уютный дом',
                targetMinor: 200000,
                savedMinor: 50000,
                color: 0xFFB7A8D9,
              ),
            ],
            wardrobe: WardrobeState(
              received: {
                for (final id in [
                  'pearl_owl',
                  'star_wanderer',
                  'starlit_academy',
                ])
                  id: now,
              },
              equipped: const {
                WardrobeSlot.companion: 'pearl_owl',
                WardrobeSlot.cape: 'star_wanderer',
              },
            ),
            world: world,
          ),
        ),
      );
      final loaded = await tester.runAsync(repo!.load);
      final c = FinanceController(repo, _Quiet(), loaded!)
        ..achievementClock = () => now;
      await tester.runAsync(c.syncWorld);
      await tester.runAsync(() => c.selectWorldGardenGoal('garden'));
      addTearDown(() async {
        c.dispose();
        await repo.close();
        await dir!.delete(recursive: true);
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final output = Platform.environment['FINORA_WORLD_CAPTURE_DIR'];
      const stageAmounts = [0, 10000, 45000, 76000, 85000, 100000];
      final pages = <String, Widget>{
        'home': const FinoraWorldScreen(),
        if (output != null) 'home-small-text2': const FinoraWorldScreen(),
        if (output != null) 'home-landscape-text2': const FinoraWorldScreen(),
        'home-settings': const WorldDecorScreen(),
        'backgrounds': const WorldBackgroundScreen(),
        'flow-map': const FlowMapScreen(),
        'garden': const WorldGardenScreen(),
        'collections': const WorldCollectionsScreen(),
        'catalog': const WorldCatalogScreen(),
        'album': const WorldAlbumScreen(),
        if (output != null)
          for (var stage = 0; stage < 6; stage++)
            'garden-stage-${stage + 1}': const WorldGardenScreen(),
      };
      for (final entry in pages.entries) {
        if (entry.key.startsWith('garden-stage-')) {
          final stage = int.parse(entry.key.split('-').last) - 1;
          await tester.runAsync(
            () => c.saveGoal(
              c.goal('garden')!.copyWith(savedMinor: stageAmounts[stage]),
            ),
          );
        }
        final small = entry.key == 'home-small-text2';
        final landscape = entry.key == 'home-landscape-text2';
        tester.view.physicalSize = small
            ? const Size(320, 640)
            : landscape
            ? const Size(740, 360)
            : const Size(390, 844);
        await tester.pumpWidget(
          FinanceScope(
            controller: c,
            child: MaterialApp(
              theme: AppTheme.build(Brightness.dark, 'coffee'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(small || landscape ? 2 : 1),
                  padding: const EdgeInsets.only(top: 24, bottom: 24),
                  viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
                ),
                child: child!,
              ),
              home: WorldTheme(
                child: RepaintBoundary(
                  key: const ValueKey('world-capture'),
                  child: entry.value,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: entry.key);
        if (output != null) {
          final context = tester.element(
            find.byKey(const ValueKey('world-capture')),
          );
          final providers = tester
              .widgetList<Image>(find.byType(Image))
              .map((image) => image.image)
              .toSet();
          await tester.runAsync(
            () => Future.wait(
              providers.map((provider) => precacheImage(provider, context)),
            ),
          );
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('world-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(output).create(recursive: true);
            await File(
              '$output/${entry.key}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
}
