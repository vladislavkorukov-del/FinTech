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

  test('legacy companions keep their IDs, artwork and achievement sources', () {
    expect(
      wardrobeItems.map((i) => i.id).toList(),
      containsAll([
        'first_coin',
        'dream_trophy',
        'mini_piggy_bank',
        'order_robot',
      ]),
    );
    const expected = {
      'first_coin': 'first_topup',
      'dream_trophy': 'goal_done',
      'mini_piggy_bank': 'saved_10000',
      'order_robot': 'order',
    };
    final ids = {for (final d in achievementDefinitions) d.id};
    for (final e in expected.entries) {
      final i = Wardrobe.item(e.key)!;
      expect(i.achievementId, e.value);
      expect(ids, contains(e.value));
      expect(i.slot, WardrobeSlot.companion);
      expect(i.layer, WardrobeLayer.frontAccessory);
      final bytes = File(i.asset).readAsBytesSync();
      expect(pngColorType(bytes), 6, reason: '${i.id}: RGBA');
    }
    expect(Directory('assets/finora/wardrobe').listSync().length, 4);
    for (final id in [
      'first_step_cap',
      'finora_legend_crown',
      'analyst_glasses',
      'mint_buds',
      'reserve_scarf',
    ]) {
      expect(Wardrobe.item(id), isNull, reason: id);
    }
  });

  test(
    'выдача: без дублей; старые плащи восстанавливаются, снятые шапки не возвращаются',
    () {
      var w = Wardrobe.sync(
        const WardrobeState(),
        got(['goal_done', 'order']),
        now: now,
      );
      expect(
        w.received.keys,
        containsAll({'dream_trophy', 'order_robot', 'digital_grid'}),
      );
      expect(
        identical(Wardrobe.sync(w, got(['goal_done', 'order']), now: now), w),
        isTrue,
      );
      w = Wardrobe.wear(w, 'dream_trophy');
      w = Wardrobe.wear(w, 'order_robot');
      expect(w.equipped, {WardrobeSlot.companion: 'order_robot'});
      expect(() => Wardrobe.wear(w, 'first_coin'), throwsFormatException);
      w = Wardrobe.takeOff(w, WardrobeSlot.companion);
      expect(w.equipped, isEmpty);
      // Old hats stay removed; a saved cape maps to the supplied stable ID.
      final old = WardrobeState.fromJson({
        'received': {
          'first_step_cap': now.toIso8601String(),
          'cape_royal_panther': now.toIso8601String(),
          'first_coin': now.toIso8601String(),
        },
        'equipped': {
          'top': 'first_step_cap',
          'cape': 'cape_royal_panther',
          'companion': 'first_coin',
        },
      });
      final clean = Wardrobe.sync(old, const AchievementState(), now: now);
      expect(clean.received.keys, containsAll(['first_coin', 'royal_panther']));
      expect(clean.received, isNot(contains('first_step_cap')));
      expect(clean.equipped, {
        WardrobeSlot.companion: 'first_coin',
        WardrobeSlot.cape: 'royal_panther',
      });
    },
  );

  test('хранение: компаньон после перезапуска', () async {
    sqfliteFfiInit();
    final temp = await Directory.systemTemp.createTemp('finora-v148-');
    final path = '${temp.path}/db';
    var repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    await repo.save(base.copyWith(achievements: got(['goal_done'])));
    var c = FinanceController(repo, _Quiet(), await repo.load())
      ..achievementClock = () => now;
    await c.syncWardrobe();
    expect(c.data.wardrobe.received.keys, contains('dream_trophy'));
    await c.wear('dream_trophy');
    c.dispose();
    await repo.close();
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    c = FinanceController(repo, _Quiet(), await repo.load());
    expect(c.data.wardrobe.equipped, {WardrobeSlot.companion: 'dream_trophy'});
    await c.resetAll();
    expect(c.data.wardrobe.received, contains('dream_trophy'));
    c.dispose();
    await repo.close();
    await temp.delete(recursive: true);
  });

  testWidgets(
    'without an equipped cape legacy companion still renders next to one Finora',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: FinoraDressed(
              size: 100,
              outfit: [Wardrobe.item('order_robot')!],
            ),
          ),
        ),
      );
      final pieces = tester.widgetList<WardrobePiece>(
        find.byType(WardrobePiece),
      );
      expect(pieces.map((p) => p.item.id), ['order_robot']);
      // The painted Finora is drawn once, with her face.
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<FinoraOrbPainter>();
      expect(painters, hasLength(1));
    },
  );

  testWidgets('экран «Гардероб Finora»: надеть и снять', (tester) async {
    sqfliteFfiInit();
    late Directory temp;
    late FinanceRepository repo;
    late FinanceController c;
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('finora-v148-ui-');
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/db',
      );
      final a = got(['goal_done']);
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
    expect(find.byKey(const ValueKey('wardrobe-count')), findsOneWidget);
    expect(find.byKey(const ValueKey('wardrobe-filter-cape')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('wardrobe-toggle-dream_trophy')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('wardrobe-toggle-dream_trophy')),
    );
    await settle();
    expect(c.data.wardrobe.equipped, {WardrobeSlot.companion: 'dream_trophy'});
    await tester.drag(
      find.byKey(const ValueKey('wardrobe-list')),
      const Offset(0, 2000),
    );
    await settle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('wardrobe-preview')),
        matching: find.byType(WardrobePiece),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('wardrobe-toggle-dream_trophy')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('wardrobe-toggle-dream_trophy')),
    );
    await settle();
    expect(c.data.wardrobe.equipped, isEmpty);
    expect(
      wardrobeCondition(Wardrobe.item('order_robot')!),
      '10 категорий за месяц, «Прочее» — не больше 20%',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      c.dispose();
      await repo.close();
      await temp.delete(recursive: true);
    });
  });

  test('«Что нового» describes both independent wardrobe slots', () {
    expect(
      WhatsNew.items.map((item) => item.$2),
      contains('Компаньоны и плащи'),
    );
  });
}
