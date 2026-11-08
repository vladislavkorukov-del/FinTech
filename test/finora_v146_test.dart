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

  test('каталог: 30 предметов, связи с настоящими достижениями', () {
    expect(wardrobeItems.length, 30);
    expect(wardrobeItems.map((i) => i.id).toSet().length, 30);
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
      'round_accounting_glasses': 'ten_records',
      'analyst_glasses': 'analyst_10',
      'fintech_visor': 'full_picture',
      'golden_perspective_glasses': 'budget_12',
      'mint_buds': 'first_account',
      'weekly_rhythm_headphones': 'streak_7',
      'cyan_pulse_headphones': 'streak_30',
      'champagne_sound_headphones': 'veteran',
      'silver_spark_crown': 'goal_done',
      'dream_crystal_crown': 'goals_3',
      'perfect_month_wreath': 'perfect_month',
      'finora_legend_crown': 'legend',
      'reserve_scarf': 'cushion_3',
      'punctuality_shield_cape': 'no_overdue',
      'veteran_mantle': 'veteran',
      'first_coin': 'first_topup',
      'dream_trophy': 'goal_done',
      'mini_piggy_bank': 'saved_10000',
      'order_robot': 'order',
    };
    for (final e in expected.entries) {
      expect(Wardrobe.item(e.key)!.achievementId, e.value, reason: e.key);
      expect(ids, contains(e.value));
    }
    final heart = Wardrobe.item('heart_glasses')!;
    expect(heart.source, isA<EventReward>());
    expect((heart.source as EventReward).live, isFalse);
    expect(heart.secret && Wardrobe.item('night_cap')!.secret, isTrue);
    for (final i in wardrobeItems) {
      final file = File(i.asset);
      expect(file.existsSync(), isTrue, reason: i.id);
      final bytes = file.readAsBytesSync();
      expect(pngColorType(bytes), 6, reason: '${i.id}: RGBA');
      expect(i.ratio, greaterThan(.5));
      expect(i.fit.width, greaterThan(.2));
    }
    // Slots: hats, crowns and headphones share «top».
    for (final c in [
      WardrobeCategory.headwear,
      WardrobeCategory.crown,
      WardrobeCategory.headphones,
    ]) {
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
    expect(w.received.keys, {'habit_flame_cap', 'weekly_rhythm_headphones'});
    expect(w.received['habit_flame_cap'], now);
    // Again — the same state, the same dates.
    final again = Wardrobe.sync(w, got(['streak_7']));
    expect(identical(again, w), isTrue);
    // Event items are not opened by achievements.
    w = Wardrobe.sync(w, got([for (final d in achievementDefinitions) d.id]));
    expect(w.received.length, 29);
    expect(w.received, isNot(contains('heart_glasses')));
  });

  test('слоты: одна вещь сверху, очки и компаньон отдельно', () {
    var w = Wardrobe.sync(
      const WardrobeState(),
      got(['first_step', 'goal_done', 'ten_records', 'first_topup']),
    );
    w = Wardrobe.wear(w, 'first_step_cap');
    w = Wardrobe.wear(w, 'round_accounting_glasses');
    w = Wardrobe.wear(w, 'first_coin');
    expect(w.equipped.length, 3);
    // A crown in «top» takes the cap off.
    w = Wardrobe.wear(w, 'silver_spark_crown');
    expect(w.equipped[WardrobeSlot.top], 'silver_spark_crown');
    expect(w.equipped.values, isNot(contains('first_step_cap')));
    expect(w.equipped[WardrobeSlot.eyes], 'round_accounting_glasses');
    // A companion in its slot replaces the coin.
    w = Wardrobe.wear(w, 'dream_trophy');
    expect(w.equipped[WardrobeSlot.companion], 'dream_trophy');
    w = Wardrobe.takeOff(w, WardrobeSlot.eyes);
    expect(w.equipped.containsKey(WardrobeSlot.eyes), isFalse);
    expect(
      () => Wardrobe.wear(w, 'finora_legend_crown'),
      throwsFormatException,
    );
    expect(Wardrobe.worn(w).map((i) => i.layer).toList(), [
      WardrobeLayer.headwear,
      WardrobeLayer.frontAccessory,
    ]);
    // JSON keeps both parts.
    final back = WardrobeState.fromJson(w.toJson());
    expect(back.equipped, w.equipped);
    expect(back.received, w.received);
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
    await repo.save(base.copyWith(achievements: got(['first_account'])));
    var c = FinanceController(repo, _Quiet(), await repo.load())
      ..achievementClock = () => now;
    expect(c.data.wardrobe.received, isEmpty);
    await c.syncWardrobe();
    expect(c.data.wardrobe.received.keys, ['mint_buds']);
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
    await c.wear('mint_buds'); // the same «top» slot
    expect(c.data.wardrobe.equipped, {WardrobeSlot.top: 'mint_buds'});
    await expectLater(c.wear('finora_legend_crown'), throwsFormatException);
    c.dispose();
    await repo.close();
    // After a restart.
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    c = FinanceController(repo, _Quiet(), await repo.load());
    expect(c.data.wardrobe.equipped, {WardrobeSlot.top: 'mint_buds'});
    expect(c.data.wardrobe.received.length, 2);
    // Deleting the operation takes nothing away; a JSON import keeps it.
    await c.deleteEntry('e1');
    expect(c.data.wardrobe.received, contains('first_step_cap'));
    final json = await repo.exportJson();
    await c.importJson(json);
    expect(c.data.wardrobe.equipped, {WardrobeSlot.top: 'mint_buds'});
    await c.resetAll();
    expect(c.data.wardrobe.received, contains('first_step_cap'));
    c.dispose();
    await repo.close();
    await temp.delete(recursive: true);
  });

  testWidgets('очки не закрывают глаза: лицо рисуется поверх', (tester) async {
    final glasses = Wardrobe.item('golden_perspective_glasses')!;
    final cap = Wardrobe.item('first_step_cap')!;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: FinoraDressed(size: 100, outfit: [cap, glasses])),
      ),
    );
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<FinoraOrbPainter>()
        .toList();
    // The body without the face, then the face alone over the glasses.
    expect(painters.where((p) => p.body && !p.face), hasLength(1));
    expect(painters.where((p) => !p.body && p.face), hasLength(1));
    final pieces = tester.widgetList<WardrobePiece>(find.byType(WardrobePiece));
    expect(pieces.map((p) => p.item.id), ['first_step_cap', glasses.id]);
    // Without glasses — one painter with the face.
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: FinoraDressed(size: 100, outfit: [cap])),
      ),
    );
    final one = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<FinoraOrbPainter>()
        .toList();
    expect(one.single.face && one.single.body, isTrue);
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
    expect(find.text('Открыто 4 из 30'), findsOneWidget);
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
    expect(wardrobeCondition(Wardrobe.item('heart_glasses')!), isNull);
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

  test('«Что нового» 1.46 — гардероб', () {
    expect(WhatsNew.items.first.$2, 'Гардероб Финоры');
  });
}
