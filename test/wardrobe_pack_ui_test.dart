import 'dart:io';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/achievements.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/wardrobe.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/wardrobe_screen.dart';
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
  sqfliteFfiInit();
  final at = DateTime(2026, 11, 8, 12);
  late Directory dir;
  late FinanceRepository repo;
  late FinanceController c;
  setUp(() async {
    await initializeDateFormatting('ru');
    dir = await Directory.systemTemp.createTemp('finora-wardrobe-ui-');
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/ledger',
    );
    await repo.save(
      FinanceData(
        accounts: const [Account(id: 'a', name: 'Карта', openingMinor: 123456)],
        members: const [Member(id: 'me', name: 'Я')],
        achievements: AchievementState(
          unlocked: {'first_step': at, 'ten_records': at, 'night': at},
        ),
        wardrobe: WardrobeState(
          received: {'lilac_ghost': at, 'moon_cat': at, 'new_year': at},
        ),
      ),
    );
    c = FinanceController(repo, _Quiet(), await repo.load())
      ..achievementClock = () => at;
    await c.syncWardrobe();
  });
  tearDown(() async {
    c.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.dark,
    Size size = const Size(360, 740),
    double scale = 1,
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
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: const WardrobeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> show(
    WidgetTester tester,
    Finder finder, {
    bool up = false,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      up ? -240 : 240,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('wardrobe-list')),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 60,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> wait(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(ready(), isTrue);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'filters expose individual pack images and two slots equip/remove independently through SQLite',
    (tester) async {
      await mount(tester);
      final capeFilter = find.byKey(const ValueKey('wardrobe-filter-cape'));
      await show(tester, capeFilter);
      await tester.tap(capeFilter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wardrobe-new_year')), findsOneWidget);
      expect(find.byKey(const ValueKey('wardrobe-first_coin')), findsNothing);
      final cape = find.byKey(const ValueKey('wardrobe-toggle-new_year'));
      await show(tester, cape);
      await tester.tap(cape);
      await wait(
        tester,
        () => c.data.wardrobe.equipped[WardrobeSlot.cape] == 'new_year',
      );
      final petFilter = find.byKey(const ValueKey('wardrobe-filter-companion'));
      await show(tester, petFilter, up: true);
      await tester.tap(petFilter);
      await tester.pumpAndSettle();
      final pet = find.byKey(const ValueKey('wardrobe-toggle-lilac_ghost'));
      await show(tester, pet);
      await tester.tap(pet);
      await wait(
        tester,
        () => c.data.wardrobe.equipped[WardrobeSlot.companion] == 'lilac_ghost',
      );
      expect(c.data.wardrobe.equipped, {
        WardrobeSlot.cape: 'new_year',
        WardrobeSlot.companion: 'lilac_ghost',
      });
      final disk = await tester.runAsync(repo.load);
      expect(disk!.wardrobe.equipped, c.data.wardrobe.equipped);
      expect(disk.accounts.single.openingMinor, 123456);
      await tester.tap(pet);
      await wait(
        tester,
        () => !c.data.wardrobe.equipped.containsKey(WardrobeSlot.companion),
      );
      expect(c.data.wardrobe.equipped, {WardrobeSlot.cape: 'new_year'});
      await show(tester, capeFilter, up: true);
      await tester.tap(capeFilter);
      await tester.pumpAndSettle();
      await show(tester, cape);
      await tester.tap(cape);
      await wait(tester, () => c.data.wardrobe.equipped.isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'all companion/cape cards stay reachable on320px, landscape and large text in both themes',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final size in [const Size(320, 640), const Size(740, 360)]) {
          await mount(tester, brightness: brightness, size: size, scale: 1.6);
          final filter = find.byKey(const ValueKey('wardrobe-filter-cape'));
          await show(tester, filter);
          await tester.tap(filter);
          await tester.pumpAndSettle();
          final lastCape = find.byKey(
            const ValueKey('wardrobe-firebird_rebel'),
          );
          await show(tester, lastCape);
          expect(tester.takeException(), isNull);
          final pets = find.byKey(const ValueKey('wardrobe-filter-companion'));
          await show(tester, pets, up: true);
          await tester.tap(pets);
          await tester.pumpAndSettle();
          final koi = find.byKey(const ValueKey('wardrobe-pearl_koi'));
          await show(tester, koi);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
    },
  );
}
