import 'dart:io';
import 'dart:typed_data';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/achievements.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/wardrobe.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/wardrobe_screen.dart';
import 'package:finora/presentation/whats_new.dart';
import 'package:finora/presentation/widgets/finora_dressed.dart';
import 'package:finora/presentation/widgets/finora_orb.dart';
import 'package:finora/presentation/widgets/voice_orb.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

const base = FinanceData(
  accounts: [Account(id: 'a', name: 'Карта')],
  categories: [Category(id: 'food', name: 'Продукты', kind: EntryKind.expense)],
  members: [Member(id: 'me', name: 'Я')],
);

final now = DateTime(2026, 11, 8, 12);

AchievementState got(List<String> ids) =>
    AchievementState(unlocked: {for (final id in ids) id: now});

/// PNG: colour type 6 (RGBA) in the IHDR.
int pngColorType(Uint8List b) => b[25];

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('каталог 1.47: 33 вещи — шапки, короны, плащи, компаньоны', () {
    expect(wardrobeItems.length, 33);
    expect(wardrobeItems.map((i) => i.id).toSet().length, 33);
    final count = <WardrobeCategory, int>{};
    for (final i in wardrobeItems) {
      count[i.category] = (count[i.category] ?? 0) + 1;
    }
    expect(count, {
      WardrobeCategory.headwear: 10,
      WardrobeCategory.crown: 4,
      WardrobeCategory.cape: 15,
      WardrobeCategory.companion: 4,
    });
    // Glasses, headphones and the old capes are gone.
    for (final id in [
      'mint_buds',
      'cyan_pulse_headphones',
      'analyst_glasses',
      'heart_glasses',
      'reserve_scarf',
      'veteran_mantle',
    ]) {
      expect(Wardrobe.item(id), isNull, reason: id);
    }
    final ids = {for (final d in achievementDefinitions) d.id};
    const expected = {
      'first_step_cap': 'first_step',
      'habit_flame_cap': 'streak_7',
      'budget_master_cap': 'budget_6',
      'cushion_sleep_cap': 'cushion_1',
      'night_cap': 'night',
      'anniversary_party_cap': 'year',
      'organizer_helmet': 'organizer',
      'steady_plus_top_hat': 'plus_3',
      'savings_piggy_cap': 'saved_10000',
      'marathon_headband': 'streak_100',
      'silver_spark_crown': 'goal_done',
      'dream_crystal_crown': 'goals_3',
      'perfect_month_wreath': 'perfect_month',
      'finora_legend_crown': 'legend',
      'first_coin': 'first_topup',
      'dream_trophy': 'goal_done',
      'mini_piggy_bank': 'saved_10000',
      'order_robot': 'order',
    };
    for (final e in expected.entries) {
      expect(Wardrobe.item(e.key)!.achievementId, e.value, reason: e.key);
      expect(ids, contains(e.value));
    }
    // Every cape: a real achievement or the New Year event; drawn behind.
    for (final i in wardrobeItems.where(
      (i) => i.category == WardrobeCategory.cape,
    )) {
      expect(i.layer, WardrobeLayer.behindCharacter);
      expect(i.slot, WardrobeSlot.cape);
      final id = i.achievementId;
      if (id == null) {
        expect(i.id, 'cape_new_year');
      } else {
        expect(ids, contains(id), reason: i.id);
      }
      // Its own fit: about twice her width, centred on her.
      expect(i.fit.width, inInclusiveRange(1.9, 2.4), reason: i.id);
      expect(i.fit.x.abs(), lessThan(.05), reason: i.id);
    }
    expect(Wardrobe.item('night_cap')!.secret, isTrue);
    for (final i in wardrobeItems) {
      final file = File(i.asset);
      expect(file.existsSync(), isTrue, reason: i.id);
      final bytes = file.readAsBytesSync();
      expect(pngColorType(bytes), 6, reason: '${i.id}: RGBA');
      expect(i.ratio, greaterThan(.5));
      expect(i.fit.width, greaterThan(.2));
    }
    // Slots: hats and crowns share «top».
    for (final c in [WardrobeCategory.headwear, WardrobeCategory.crown]) {
      expect(
        wardrobeItems
            .where((i) => i.category == c)
            .every((i) => i.slot == WardrobeSlot.top),
        isTrue,
      );
    }
    expect(WardrobeLayer.values.map((l) => l.name), [
      'behindCharacter',
      'body',
      'cape',
      'headwear',
      'eyesAccessory',
      'frontAccessory',
      'particles',
    ]);
    // Each item has its own fit, not one per category.
    final caps = wardrobeItems
        .where((i) => i.category == WardrobeCategory.headwear)
        .map((i) => '${i.fit.width}/${i.fit.x}/${i.fit.y}/${i.fit.rotation}')
        .toSet();
    expect(caps.length, greaterThan(5));
  });

  test('награды: открываются с достижением, без дублей, и за старые', () {
    var w = Wardrobe.sync(const WardrobeState(), got(['streak_7']));
    expect(w.received.keys, {'habit_flame_cap'});
    expect(w.received['habit_flame_cap'], now);
    // Again — the same state, the same dates.
    final again = Wardrobe.sync(w, got(['streak_7']));
    expect(identical(again, w), isTrue);
    // The New Year cape is not opened by achievements.
    w = Wardrobe.sync(
      w,
      got([for (final d in achievementDefinitions) d.id]),
      now: now,
    );
    expect(w.received.length, 32);
    expect(w.received, isNot(contains('cape_new_year')));
  });

  test('новогодний плащ: с 15 декабря по 15 января', () {
    for (final (day, open) in [
      (DateTime(2026, 12, 14), false),
      (DateTime(2026, 12, 15), true),
      (DateTime(2026, 12, 31, 23), true),
      (DateTime(2027, 1, 15), true),
      (DateTime(2027, 1, 16), false),
      (DateTime(2027, 7, 1), false),
    ]) {
      final w = Wardrobe.sync(
        const WardrobeState(),
        const AchievementState(),
        now: day,
      );
      expect(w.received.containsKey('cape_new_year'), open, reason: '$day');
    }
    // Once received it stays after the holidays.
    final got = Wardrobe.sync(
      const WardrobeState(),
      const AchievementState(),
      now: DateTime(2026, 12, 20),
    );
    final later = Wardrobe.sync(
      got,
      const AchievementState(),
      now: DateTime(2027, 3, 1),
    );
    expect(later.received, contains('cape_new_year'));
    expect(
      wardrobeCondition(Wardrobe.item('cape_new_year')!),
      'Загляните в Finora с 15 декабря по 15 января',
    );
  });

  test('слоты: одна вещь сверху, плащ и компаньон отдельно', () {
    var w = Wardrobe.sync(
      const WardrobeState(),
      got(['first_step', 'goal_done', 'ten_records', 'first_topup']),
      now: now,
    );
    w = Wardrobe.wear(w, 'first_step_cap');
    w = Wardrobe.wear(w, 'cape_star_wanderer');
    w = Wardrobe.wear(w, 'first_coin');
    expect(w.equipped.length, 3);
    // A crown in «top» takes the cap off.
    w = Wardrobe.wear(w, 'silver_spark_crown');
    expect(w.equipped[WardrobeSlot.top], 'silver_spark_crown');
    expect(w.equipped.values, isNot(contains('first_step_cap')));
    // Another cape replaces the first one.
    w = Wardrobe.wear(w, 'cape_emerald_wood');
    expect(w.equipped[WardrobeSlot.cape], 'cape_emerald_wood');
    w = Wardrobe.wear(w, 'dream_trophy');
    expect(w.equipped[WardrobeSlot.companion], 'dream_trophy');
    expect(
      () => Wardrobe.wear(w, 'finora_legend_crown'),
      throwsFormatException,
    );
    // Back to front: cape, crown, companion.
    expect(Wardrobe.worn(w).map((i) => i.layer).toList(), [
      WardrobeLayer.behindCharacter,
      WardrobeLayer.headwear,
      WardrobeLayer.frontAccessory,
    ]);
    w = Wardrobe.takeOff(w, WardrobeSlot.cape);
    expect(w.equipped.containsKey(WardrobeSlot.cape), isFalse);
    final back = WardrobeState.fromJson(w.toJson());
    expect(back.equipped, w.equipped);
    expect(back.received, w.received);
    // A saved «eyes» slot from 1.46 is ignored, its glasses forgotten.
    final old = WardrobeState.fromJson({
      'received': {'analyst_glasses': now.toIso8601String()},
      'equipped': {'eyes': 'analyst_glasses'},
    });
    expect(old.equipped, isEmpty);
    expect(
      Wardrobe.sync(old, const AchievementState(), now: now).received,
      isEmpty,
    );
  });

  test('хранение: достижение → предмет, надетое после перезапуска', () async {
    sqfliteFfiInit();
    final temp = await Directory.systemTemp.createTemp('finora-v146-');
    final path = '${temp.path}/db';
    var repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    // Before 1.46: achievements are there, the wardrobe is empty.
    await repo.save(base.copyWith(achievements: got(['goal_done'])));
    var c = FinanceController(repo, _Quiet(), await repo.load())
      ..achievementClock = () => now;
    expect(c.data.wardrobe.received, isEmpty);
    await c.syncWardrobe();
    // goal_done → crown and trophy; «Мои деньги» (the account) → a cape.
    expect(
      c.data.wardrobe.received.keys,
      containsAll(['silver_spark_crown', 'dream_trophy', 'cape_pirate_tides']),
    );
    // A new achievement brings its item at once.
    await c.saveEntry(
      FinanceEntry(
        id: 'e1',
        kind: EntryKind.expense,
        amountMinor: 10000,
        currency: 'RUB',
        accountId: 'a',
        categoryId: 'food',
        date: now,
      ),
    );
    expect(c.data.achievements.unlocked, contains('first_step'));
    expect(c.data.wardrobe.received, contains('first_step_cap'));
    await c.wear('first_step_cap');
    await c.wear('silver_spark_crown'); // the same «top» slot
    expect(c.data.wardrobe.equipped, {WardrobeSlot.top: 'silver_spark_crown'});
    await expectLater(c.wear('finora_legend_crown'), throwsFormatException);
    c.dispose();
    await repo.close();
    // After a restart.
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    c = FinanceController(repo, _Quiet(), await repo.load());
    expect(c.data.wardrobe.equipped, {WardrobeSlot.top: 'silver_spark_crown'});
    expect(c.data.wardrobe.received.length, 4);
    // Deleting the operation takes nothing away; a JSON import keeps it.
    await c.deleteEntry('e1');
    expect(c.data.wardrobe.received, contains('first_step_cap'));
    final json = await repo.exportJson();
    await c.importJson(json);
    expect(c.data.wardrobe.equipped, {WardrobeSlot.top: 'silver_spark_crown'});
    await c.resetAll();
    expect(c.data.wardrobe.received, contains('first_step_cap'));
    c.dispose();
    await repo.close();
    await temp.delete(recursive: true);
  });

  testWidgets('слои: плащ за Финорой, корона и компаньон перед ней', (
    tester,
  ) async {
    final outfit = Wardrobe.worn(
      Wardrobe.wear(
        Wardrobe.wear(
          Wardrobe.wear(
            WardrobeState(
              received: {
                for (final id in [
                  'cape_royal_panther',
                  'finora_legend_crown',
                  'order_robot',
                ])
                  id: now,
              },
            ),
            'cape_royal_panther',
          ),
          'finora_legend_crown',
        ),
        'order_robot',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: FinoraDressed(size: 100, outfit: outfit)),
      ),
    );
    final stack = tester.widget<Stack>(
      find
          .descendant(
            of: find.byType(FinoraOutfit),
            matching: find.byType(Stack),
          )
          .first,
    );
    String name(Widget w) => switch (w) {
      WardrobePiece(:final item) => item.id,
      CustomPaint(:final painter) when painter is FinoraOrbPainter => 'finora',
      _ => '?',
    };
    expect(stack.children.map(name).toList(), [
      'cape_royal_panther',
      'finora',
      'finora_legend_crown',
      'order_robot',
    ]);
  });

  testWidgets('Финора в меню одета: нижняя панель', (tester) async {
    sqfliteFfiInit();
    late Directory temp;
    late FinanceRepository repo;
    late FinanceController c;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('finora-v147-bar-');
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/db',
      );
      final a = got(['legend', 'veteran']);
      var w = Wardrobe.sync(const WardrobeState(), a, now: now);
      w = Wardrobe.wear(
        Wardrobe.wear(w, 'finora_legend_crown'),
        'cape_royal_panther',
      );
      await repo.save(base.copyWith(achievements: a, wardrobe: w));
      c = FinanceController(repo, _Quiet(), await repo.load());
    });
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: VoiceOrb(size: 54, onTap: () {}, onLongPress: () {}),
            ),
          ),
        ),
      ),
    );
    final pieces = tester.widgetList<WardrobePiece>(find.byType(WardrobePiece));
    expect(pieces.map((p) => p.item.id), [
      'cape_royal_panther',
      'finora_legend_crown',
    ]);
    // Narrower in the bar: the tabs are on both sides.
    expect(pieces.first.spread, lessThan(1));
    // Taken off — gone from the menu too.
    await tester.runAsync(() => c.takeOff(WardrobeSlot.cape));
    await tester.pump();
    expect(
      tester
          .widgetList<WardrobePiece>(find.byType(WardrobePiece))
          .map((p) => p.item.id),
      ['finora_legend_crown'],
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      c.dispose();
      await repo.close();
      await temp.delete(recursive: true);
    });
  });

  testWidgets('экран «Гардероб Finora»: фильтры, надеть, снять, ???', (
    tester,
  ) async {
    sqfliteFfiInit();
    late Directory temp;
    late FinanceRepository repo;
    late FinanceController c;
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('finora-v146-ui-');
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/db',
      );
      final a = got(['first_step', 'goal_done', 'legend']);
      await repo.save(
        base.copyWith(
          achievements: a,
          wardrobe: Wardrobe.sync(const WardrobeState(), a),
        ),
      );
      c = FinanceController(repo, _Quiet(), await repo.load());
    });
    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: const MaterialApp(home: WardrobeScreen()),
      ),
    );
    await settle();
    expect(find.text('Открыто 4 из 33'), findsOneWidget);
    expect(find.byKey(const ValueKey('wardrobe-preview')), findsOneWidget);

    // Wear the cap.
    await tester.tap(
      find.byKey(const ValueKey('wardrobe-toggle-first_step_cap')),
    );
    await settle();
    expect(c.data.wardrobe.equipped[WardrobeSlot.top], 'first_step_cap');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('wardrobe-preview')),
        matching: find.byType(WardrobePiece),
      ),
      findsOneWidget,
    );
    expect(find.text('Надето'), findsOneWidget);

    // «Легендарные»: only legendary items; the crown replaces the cap.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('wardrobe-filter-legendary')),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('wardrobe-filters')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('wardrobe-filter-legendary')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wardrobe-filter-legendary')));
    await settle();
    expect(find.byKey(const ValueKey('wardrobe-first_step_cap')), findsNothing);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('wardrobe-toggle-finora_legend_crown')),
      find.byKey(const ValueKey('wardrobe-list')),
      const Offset(0, -120),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('wardrobe-toggle-finora_legend_crown')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('wardrobe-toggle-finora_legend_crown')),
    );
    await settle();
    expect(c.data.wardrobe.equipped, {WardrobeSlot.top: 'finora_legend_crown'});
    await tester.ensureVisible(
      find.byKey(const ValueKey('wardrobe-toggle-finora_legend_crown')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('wardrobe-toggle-finora_legend_crown')),
    );
    await settle();
    expect(c.data.wardrobe.equipped, isEmpty);

    // Secrets stay «???».
    expect(wardrobeSourceText(Wardrobe.item('night_cap')!, open: false), '???');
    expect(wardrobeCondition(Wardrobe.item('night_cap')!), isNull);
    expect(
      wardrobeCondition(Wardrobe.item('marathon_headband')!),
      '100 дней подряд с финансовыми делами',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      c.dispose();
      await repo.close();
      await temp.delete(recursive: true);
    });
  });

  testWidgets('крупный шрифт: карточки не переполняются', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 740),
            textScaler: TextScaler.linear(1.6),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                return Center(
                  child: SizedBox(
                    width: 164,
                    height: 166 + 150 * scale,
                    child: WardrobeCard(
                      item: Wardrobe.item('perfect_month_wreath')!,
                      open: false,
                      worn: false,
                      onToggle: () {},
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('«Что нового» 1.47 — меню и плащи', () {
    final titles = WhatsNew.items.map((i) => i.$2).toList();
    expect(titles.first, 'Финора одета и в меню');
    expect(titles, containsAll(['15 плащей', 'Гардероб Финоры']));
  });
}
