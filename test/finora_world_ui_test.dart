import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/achievements.dart';
import 'package:finora/domain/finora_world.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/wardrobe.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/world/finora_world_screen.dart';
import 'package:finora/presentation/screens/world/world_collections.dart';
import 'package:finora/presentation/screens/world/world_customization.dart';
import 'package:finora/presentation/screens/world/world_garden_album.dart';
import 'package:finora/presentation/screens/world/world_home_scene.dart';
import 'package:finora/presentation/screens/world/world_reviews_settings.dart';
import 'package:finora/presentation/screens/tutorial.dart';
import 'package:finora/presentation/screens/wardrobe_screen.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/finora_dressed.dart';
import 'package:finora/presentation/widgets/entry_tile.dart';
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
  sqfliteFfiInit();
  final now = DateTime(2026, 11, 8, 12);
  late Directory dir;
  late FinanceRepository repo;
  late FinanceController c;

  setUp(() async {
    await initializeDateFormatting('ru');
    dir = await Directory.systemTemp.createTemp('finora-world-ui-');
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/ledger',
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
    world = WorldEngine.purchase(world, 'crystal', points: 150);
    await repo.save(
      FinanceData(
        accounts: const [Account(id: 'a', name: 'Карта', openingMinor: 123456)],
        members: const [Member(id: 'me', name: 'Я')],
        categories: const [
          Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
        ],
        goals: const [
          Goal(
            id: 'garden',
            name: 'Путешествие к северному сиянию',
            targetMinor: 100000,
            savedMinor: 50000,
          ),
        ],
        achievements: AchievementState(unlocked: {'first_step': now}),
        wardrobe: WardrobeState(
          received: {'lilac_ghost': now},
          equipped: const {WardrobeSlot.companion: 'lilac_ghost'},
        ),
        world: world,
      ),
    );
    c = FinanceController(repo, _Quiet(), await repo.load())
      ..achievementClock = () => now;
    await c.syncWorld();
  });

  tearDown(() async {
    c.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester,
    Widget home, {
    Brightness brightness = Brightness.dark,
    Size size = const Size(360, 740),
    double scale = 1,
    bool reduced = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.build(brightness, 'coffee'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: home,
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

  testWidgets(
    'world pages remain usable at320px and landscape with large text in both themes',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final size in [const Size(320, 640), const Size(740, 360)]) {
          for (final page in <Widget>[
            const FinoraWorldScreen(),
            const WorldDecorScreen(),
            const WorldCatalogScreen(),
            const WorldOutfitsScreen(),
            const WorldCollectionsScreen(),
            const WorldGardenScreen(),
            const WorldAlbumScreen(),
            const WorldReviewScreen(),
            const WorldSettingsScreen(),
          ]) {
            await mount(
              tester,
              page,
              brightness: brightness,
              size: size,
              scale: 1.6,
            );
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -1800),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$page at $size, $brightness',
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
        }
      }
    },
  );

  testWidgets(
    'home decoration and outfits write through the existing SQLite controller',
    (tester) async {
      await mount(tester, const WorldDecorScreen());
      await tester.tap(find.byKey(const ValueKey('world-background-pearl')));
      await wait(tester, () => c.data.world.background == 'pearl');
      final db = await tester.runAsync(repo.load);
      expect(db!.world.background, 'pearl');

      await mount(tester, const WorldOutfitsScreen());
      await tester.tap(find.byKey(const ValueKey('world-save-outfit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('world-outfit-name')),
        'Лавандовый вечер',
      );
      await tester.tap(find.byKey(const ValueKey('world-outfit-confirm')));
      await wait(tester, () => c.data.world.outfits.length == 1);
      final savedId = c.data.world.outfits.single.id;
      await tester.runAsync(() => c.takeOff(WardrobeSlot.companion));
      await tester.pumpAndSettle();
      final apply = find.byKey(ValueKey('world-apply-outfit-$savedId'));
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await wait(
        tester,
        () => c.data.wardrobe.equipped[WardrobeSlot.companion] == 'lilac_ghost',
      );
      expect(
        (await tester.runAsync(repo.load))!.world.outfits.single.name,
        'Лавандовый вечер',
      );
      expect(c.balance, 123456);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'pet tap and rest use the real selected companion; quiet settings persist',
    (tester) async {
      await mount(tester, const FinoraWorldScreen());
      expect(find.byType(WorldHomeScene), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('world-finora-tap')));
      await tester.pump();
      expect(
        tester
            .widget<FinoraDressed>(find.byType(FinoraDressed))
            .companionSleeping,
        isFalse,
      );
      final rest = find.byKey(const ValueKey('world-pet-rest'));
      await tester.ensureVisible(rest);
      await tester.tap(rest);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FinoraDressed>(find.byType(FinoraDressed))
            .companionSleeping,
        isTrue,
      );
      await tester.pump(const Duration(seconds: 1));

      await mount(tester, const WorldSettingsScreen());
      await tester.tap(find.byKey(const ValueKey('world-reduce-motion')));
      await wait(tester, () => c.data.world.reducedMotion);
      await tester.tap(find.byKey(const ValueKey('world-remarks')));
      await wait(tester, () => !c.data.world.remarks);
      final stored = await tester.runAsync(repo.load);
      expect(stored!.world.reducedMotion, isTrue);
      expect(stored.world.remarks, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'garden uses live financial goals and opens the existing editor',
    (tester) async {
      await mount(tester, const WorldGardenScreen());
      expect(find.text('50% накоплено'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('world-plant-garden')));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'review confirmation is period-idempotent and its figures open financial sources',
    (tester) async {
      await mount(tester, const WorldReviewScreen());
      final button = find.byKey(const ValueKey('world-review-confirm'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      final event = 'review:week:${WorldCatalog.weekKey(now)}';
      await wait(tester, () => c.data.world.rewards.containsKey(event));
      final sparks = c.data.world.sparks;
      await tester.runAsync(() => c.confirmWorldReview('week'));
      expect(c.data.world.sparks, sparks);
      await tester.ensureVisible(find.text('Доходы'));
      await tester.tap(find.text('Доходы'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('world-review-source')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'review source retains exact currency, period, kind and posted filters',
    (tester) async {
      final start = DateTime.parse(WorldCatalog.weekKey(now));
      await tester.runAsync(() async {
        await c.saveAccount(const Account(id: 'b', name: 'Второй счёт'));
        for (final entry in [
          FinanceEntry(
            id: 'rub',
            kind: EntryKind.expense,
            amountMinor: 2500,
            accountId: 'a',
            currency: 'RUB',
            categoryId: 'food',
            date: start,
            memberId: 'me',
          ),
          FinanceEntry(
            id: 'usd',
            kind: EntryKind.expense,
            amountMinor: 500,
            accountId: 'a',
            currency: 'USD',
            categoryId: 'food',
            date: start,
            memberId: 'me',
          ),
          FinanceEntry(
            id: 'pending',
            kind: EntryKind.expense,
            amountMinor: 999,
            accountId: 'a',
            currency: 'RUB',
            categoryId: 'food',
            date: start,
            memberId: 'me',
            status: 'pending',
          ),
          FinanceEntry(
            id: 'transfer',
            kind: EntryKind.transfer,
            amountMinor: 100,
            accountId: 'a',
            toAccountId: 'b',
            currency: 'RUB',
            date: start,
            memberId: 'me',
          ),
        ]) {
          // Foreign-currency entries require a matching account.
          if (entry.currency == 'USD') {
            await c.saveAccount(
              const Account(id: 'usd-account', name: 'USD', currency: 'USD'),
            );
            await c.saveEntry(entry.copyWith(accountId: 'usd-account'));
          } else {
            await c.saveEntry(entry);
          }
        }
      });
      await mount(tester, const WorldReviewScreen());
      await tester.tap(find.text('25 ₽'));
      await tester.pumpAndSettle();
      final source = tester.widgetList<EntryTile>(find.byType(EntryTile));
      expect(source.map((e) => e.entry.id), ['rub']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'return from a completed garden goal celebrates briefly, then stops on background',
    (tester) async {
      await mount(tester, const FinoraWorldScreen(), reduced: false);
      final garden = find.byKey(const ValueKey('world-destination-2'));
      await tester.ensureVisible(garden);
      await tester.pumpAndSettle();
      await tester.tap(garden);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => c.saveGoal(c.goal('garden')!.copyWith(savedMinor: 100000)),
      );
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.widget<WorldHomeScene>(find.byType(WorldHomeScene)).celebrating,
        isTrue,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(
        tester.widget<WorldHomeScene>(find.byType(WorldHomeScene)).celebrating,
        isFalse,
      );
      final sceneContext = tester.element(find.byType(WorldHomeScene));
      expect(TickerMode.valuesOf(sceneContext).enabled, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'calm preference reaches reused wardrobe without changing global settings',
    (tester) async {
      await tester.runAsync(() => c.worldSettings(reducedMotion: true));
      await mount(tester, const FinoraWorldScreen(), reduced: false);
      final wardrobe = find.byKey(const ValueKey('world-destination-0'));
      await tester.ensureVisible(wardrobe);
      await tester.tap(wardrobe);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(WardrobeScreen));
      expect(MediaQuery.disableAnimationsOf(context), isTrue);
      expect(TickerMode.valuesOf(context).enabled, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'skipping tutorial gives no reward; actual final completion gives one',
    (tester) async {
      await tester.runAsync(
        () => c.mutate((d) {
          final rewards = Map<String, WorldReward>.of(d.world.rewards)
            ..remove('tutorial');
          return d.copyWith(world: d.world.copyWith(rewards: rewards));
        }),
      );
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const TutorialScreen()),
              ),
              child: const Text('Launch tutorial'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Launch tutorial'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tutorial-skip')));
      await tester.pumpAndSettle();
      expect(c.data.world.rewards.containsKey('tutorial'), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const TutorialScreen()),
              ),
              child: const Text('Launch tutorial'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Launch tutorial'));
      await tester.pumpAndSettle();
      for (var i = 0; i < TutorialScreen.pageCount - 1; i++) {
        await tester.tap(find.byKey(const ValueKey('tutorial-next')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('tutorial-done')));
      await wait(tester, () => c.data.world.rewards.containsKey('tutorial'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
