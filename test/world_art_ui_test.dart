import 'dart:io';
import 'dart:ui' as ui;

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finora_world.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/wardrobe.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/wardrobe_screen.dart';
import 'package:finora/presentation/screens/world/finora_world_screen.dart';
import 'package:finora/presentation/screens/world/world_art.dart';
import 'package:finora/presentation/screens/world/world_customization.dart';
import 'package:finora/presentation/screens/world/world_reviews_settings.dart';
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
  sqfliteFfiInit();
  final now = DateTime(2026, 11, 8, 12);
  late Directory dir;
  late FinanceRepository repo;
  late FinanceController c;
  setUp(() async {
    await initializeDateFormatting('ru');
    dir = await Directory.systemTemp.createTemp('finora-world-art-');
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/db',
    );
    var world = const WorldState();
    for (final id in [
      'first_goal',
      'first_payment',
      'categorized',
      'tutorial',
      'goal_reward:1',
      'goal_reward:2',
      'goal_reward:3',
      for (final game in ['constellation', 'parcel', 'expedition'])
        for (var level = 0; level < 3; level++) 'game:$game:$level',
    ]) {
      world = WorldEngine.reward(world, id, now: now);
    }
    for (final art in worldBackgroundArt) {
      world = WorldEngine.purchase(world, art.cosmeticId, points: 1000);
    }
    await repo.save(
      FinanceData(
        accounts: const [Account(id: 'a', name: 'Карта', openingMinor: 123456)],
        members: const [Member(id: 'me', name: 'Я')],
        wardrobe: WardrobeState(
          received: {'moon_cat': now, 'star_wanderer': now},
          equipped: const {
            WardrobeSlot.companion: 'moon_cat',
            WardrobeSlot.cape: 'star_wanderer',
          },
        ),
        world: world,
      ),
    );
    c = FinanceController(repo, _Quiet(), await repo.load())
      ..achievementClock = () => now;
  });
  tearDown(() async {
    c.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });
  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark, 'coffee'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const ValueKey('world-art-capture'),
            child: page,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> wait(WidgetTester tester, bool Function() predicate) async {
    for (var i = 0; i < 100 && !predicate(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(predicate(), isTrue);
    await tester.pumpAndSettle();
  }

  test(
    'resource source IDs and legacy selections both map without resetting backgrounds',
    () {
      expect(worldBackgroundArt, hasLength(6));
      for (final art in worldBackgroundArt) {
        expect(WorldArt.background(art.id), same(art));
        expect(WorldArt.background(art.cosmeticId), same(art));
        expect(File(art.asset).existsSync(), isTrue);
      }
      expect(WorldArt.background('obsolete').cosmeticId, 'mint');
      expect(WorldArt.background('aurora').width, 1052);
      expect(WorldArt.background('aurora').height, 1495);
    },
  );
  testWidgets(
    'all six real backgrounds keep the current character and fit small/landscape',
    (tester) async {
      final outfit = Map<WardrobeSlot, String>.of(c.data.wardrobe.equipped);
      for (final size in [const Size(320, 640), const Size(740, 360)]) {
        for (final art in worldBackgroundArt) {
          await tester.runAsync(() => c.configureWorld(art.cosmeticId, {}));
          await mount(
            tester,
            const FinoraWorldScreen(),
            size: size,
            scale: 1.6,
          );
          expect(
            find.byKey(ValueKey('world-background-layer-${art.id}')),
            findsOneWidget,
          );
          expect(c.data.wardrobe.equipped, outfit);
          expect(c.balance, 123456);
          expect(tester.takeException(), isNull, reason: '${art.id} $size');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
    },
  );
  testWidgets(
    'the six-preview selector persists without changing a pet or real balance',
    (tester) async {
      await mount(tester, const WorldBackgroundScreen());
      final select = find.byKey(const ValueKey('world-background-aurora'));
      await tester.scrollUntilVisible(select, 220, maxScrolls: 30);
      await tester.ensureVisible(select);
      await tester.tap(select);
      await wait(tester, () => c.data.world.background == 'aurora');
      final loaded = await tester.runAsync(repo.load);
      expect(loaded!.world.background, 'aurora');
      expect(loaded.wardrobe.equipped, c.data.wardrobe.equipped);
      expect(c.balance, 123456);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'pet route is the actual wardrobe filter and settings do not fake sound',
    (tester) async {
      await mount(tester, const FinoraWorldScreen());
      final pet = find.byKey(const ValueKey('world-nav-pets'));
      await tester.ensureVisible(pet);
      await tester.tap(pet);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WardrobeScreen>(find.byType(WardrobeScreen))
            .initialCategory,
        WardrobeCategory.companion,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, const WorldSettingsScreen());
      expect(find.text('Музыка'), findsOneWidget);
      expect(find.text('Звуки'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNWidgets(3));
      expect(
        find.text('Музыкальных дорожек в наборе пока нет.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('current home PNG layers decode before visual verification', (
    tester,
  ) async {
    final output = Platform.environment['FINORA_ART_CAPTURE_DIR'];
    if (output != null) await tester.runAsync(loadScreenshotFonts);
    await mount(tester, const FinoraWorldScreen());
    final context = tester.element(find.byType(FinoraWorldScreen));
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
    final images = tester
        .renderObjectList<RenderImage>(find.byType(RawImage))
        .toList();
    expect(images.length, greaterThan(12));
    expect(images.every((image) => image.image != null), isTrue);
    expect(tester.takeException(), isNull);
    if (output != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('world-art-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File(
          '$output/home.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
