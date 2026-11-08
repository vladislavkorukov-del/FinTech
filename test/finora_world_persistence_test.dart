import 'dart:convert';
import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/finora_world.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/wardrobe.dart';
import 'package:finora/domain/world_games.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  int calls = 0;
  @override
  Future<void> sync(FinanceData data) async {
    calls++;
  }
}

void main() {
  sqfliteFfiInit();
  final now = DateTime(2026, 11, 8, 12);
  final base = FinanceData(
    accounts: const [Account(id: 'a', name: 'Карта', openingMinor: 100000)],
    categories: const [
      Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
      Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
    ],
    members: const [Member(id: 'me', name: 'Я')],
    wardrobe: WardrobeState(
      received: {'moon_cat': now, 'frost_queen': now},
      equipped: const {WardrobeSlot.companion: 'moon_cat'},
    ),
  );
  late Directory dir;
  late FinanceRepository repo;
  late FinanceController c;
  late _Quiet notifications;
  String getPath() => '${dir.path}/ledger.db';
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('finora-world-storage-');
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: getPath(),
    );
    await repo.save(base);
    notifications = _Quiet();
    c = FinanceController(repo, notifications, await repo.load())
      ..achievementClock = () => now;
  });
  tearDown(() async {
    c.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });
  Future<void> restart() async {
    c.dispose();
    await repo.close();
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: getPath(),
    );
    c = FinanceController(repo, notifications, await repo.load())
      ..achievementClock = () => now;
  }

  test(
    'old v5 database adopts empty world without modifying ledger or wardrobe',
    () async {
      final db = await databaseFactoryFfi.openDatabase(getPath());
      await db.delete(
        'settings',
        where: 'key = ?',
        whereArgs: ['finora_world'],
      );
      final before = (await repo.load()).toJson()..remove('world');
      await restart();
      expect(c.data.world.toJson(), const WorldState().toJson());
      expect(c.data.toJson()..remove('world'), before);
      expect(c.data.wardrobe.equipped[WardrobeSlot.companion], 'moon_cat');
    },
  );

  test(
    'same-queue concurrent claims and purchases charge and reward once',
    () async {
      await Future.wait(
        List.generate(12, (_) => c.confirmWorldReview('month')),
      );
      expect(c.data.world.rewards.keys, ['review:month:2026-10']);
      expect(c.data.world.sparks, 25);
      await Future.wait(
        List.generate(8, (_) => c.purchaseWorldCosmetic('crystal')),
      );
      expect(c.data.world.sparks, 10);
      expect(c.data.world.purchases, {'crystal'});
      expect(
        notifications.calls,
        0,
        reason: 'world commits do not reschedule bank reminders',
      );
      final committed = c.data.world.toJson();
      await expectLater(c.purchaseWorldCosmetic('moon'), throwsFormatException);
      expect(c.data.world.toJson(), committed);
      expect((await repo.load()).world.toJson(), committed);
    },
  );

  test(
    'scene, slots, settings, game steps and multiple outfits survive restart',
    () async {
      await c.completeWorldTutorial();
      await c.purchaseWorldCosmetic('crystal');
      await c.configureWorld('pearl', {'shelf': 'crystal'});
      await c.saveWorldOutfit('Кот');
      await c.wear('frost_queen');
      await c.saveWorldOutfit('Кот и плащ');
      final looks = c.data.world.outfits;
      await c.applyWorldOutfit(looks.first.id);
      expect(c.data.wardrobe.equipped, {WardrobeSlot.companion: 'moon_cat'});
      await c.applyWorldOutfit(looks.last.id);
      await c.saveWorldGame('parcel:0', [0, 102]);
      await c.worldSettings(
        reducedMotion: true,
        remarks: false,
        hidePrivate: false,
      );
      final before = c.data.toJson();
      await restart();
      expect(c.data.toJson(), before);
      expect(c.data.world.games['parcel:0'], [0, 102]);
      expect(
        c.data.world.memories.keys,
        containsAll(['pet:first', 'home:first']),
      );
      await c.deleteWorldOutfit(looks.first.id);
      expect(c.data.world.outfits.single.id, looks.last.id);
      await c.saveWorldGame('parcel:0', [0, 102, 206]);
      expect(c.data.world.rewards, contains('game:parcel:0'));
      await restart();
      expect(
        WorldGames.complete('parcel:0', c.data.world.games['parcel:0']!),
        isTrue,
      );
    },
  );

  test(
    'failed SQLite write rolls back world, purchases and financial snapshot together',
    () async {
      final before = c.data.toJson();
      final db = await databaseFactoryFfi.openDatabase(getPath());
      await db.execute(
        "CREATE TRIGGER reject_world BEFORE INSERT ON settings WHEN NEW.key = 'finora_world' BEGIN SELECT RAISE(ABORT, 'simulated disk failure'); END",
      );
      await expectLater(
        c.completeWorldTutorial(),
        throwsA(isA<DatabaseException>()),
      );
      expect(c.data.toJson(), before);
      expect((await repo.load()).toJson(), before);
      await db.execute('DROP TRIGGER reject_world');
      await c.completeWorldTutorial();
      expect(c.data.world.rewards.length, 1);
      expect(c.data.world.sparks, 20);
    },
  );

  test(
    'stale JSON/DB restore and repeat import preserve rewards and cosmetics',
    () async {
      await c.completeWorldTutorial();
      final staleJson = await repo.exportJson();
      final staleDb = await repo.backupDatabase('${dir.path}/old.db');
      await c.confirmWorldReview('month');
      await c.purchaseWorldCosmetic('crystal');
      await c.configureWorld('pearl', {'left': 'crystal'});
      await c.saveWorldOutfit('Старый друг');
      final before = c.data.world.toJson();
      await c.importJson(staleJson);
      await c.importJson(staleJson);
      await c.restore(staleDb);
      expect(c.data.world.toJson(), before);
      await restart();
      expect(c.data.world.toJson(), before);
      await c.completeWorldTutorial();
      expect(c.data.world.toJson(), before);
    },
  );

  test(
    'restore merges immutable rewards in the same single SQLite commit',
    () async {
      final stale = await repo.exportJson();
      await c.completeWorldTutorial();
      final db = await databaseFactoryFfi.openDatabase(getPath());
      await db.execute('CREATE TABLE world_write_count(n INTEGER NOT NULL)');
      await db.execute('INSERT INTO world_write_count VALUES(0)');
      await db.execute(
        "CREATE TRIGGER count_world AFTER INSERT ON settings WHEN NEW.key = 'finora_world' BEGIN UPDATE world_write_count SET n = n + 1; END",
      );
      await c.importJson(stale);
      final row = (await db.query('world_write_count')).single;
      expect(
        row['n'],
        1,
        reason:
            'A stale snapshot must never be committed before its reward ledger is merged',
      );
      expect((await repo.load()).world.rewards, contains('tutorial'));
    },
  );

  test(
    'failed restore keeps both current financial rows and reward receipts',
    () async {
      final incoming =
          jsonDecode(await repo.exportJson()) as Map<String, dynamic>;
      ((incoming['data'] as Map)['accounts'] as List).first['name'] =
          'Восстановленный счёт';
      await c.completeWorldTutorial();
      final before = c.data.toJson();
      final db = await databaseFactoryFfi.openDatabase(getPath());
      await db.execute(
        "CREATE TRIGGER reject_restore BEFORE INSERT ON settings WHEN NEW.key = 'finora_world' BEGIN SELECT RAISE(ABORT, 'simulated restore failure'); END",
      );
      await expectLater(
        c.importJson(jsonEncode(incoming)),
        throwsA(isA<DatabaseException>()),
      );
      expect(c.data.toJson(), before);
      expect((await repo.load()).toJson(), before);
      await db.execute('DROP TRIGGER reject_restore');
      await c.importJson(jsonEncode(incoming));
      expect(c.data.accounts.single.name, 'Восстановленный счёт');
      expect(c.data.world.rewards, contains('tutorial'));
    },
  );

  test(
    'JSON, SQLite and full CSV include world and restore into a fresh install',
    () async {
      await c.completeWorldTutorial();
      await c.purchaseWorldCosmetic('tea');
      await c.configureWorld('pearl', {'right': 'tea'});
      await c.saveWorldOutfit('Любимый');
      await c.saveWorldGame('expedition:2', [2, 1]);
      final expected = c.data.world.toJson();
      final json = await repo.exportJson();
      final csv = await repo.exportFullCsv();
      final db = await repo.backupDatabase('${dir.path}/complete.db');
      for (final format in ['json', 'csv', 'db']) {
        final other = await FinanceRepository.open(
          factory: databaseFactoryFfi,
          path: '${dir.path}/$format.db',
        );
        await other.save(
          const FinanceData(
            members: [Member(id: 'me', name: 'Я')],
          ),
        );
        final controller = FinanceController(
          other,
          _Quiet(),
          await other.load(),
        )..achievementClock = () => now;
        try {
          if (format == 'json') await controller.importJson(json);
          if (format == 'csv') await controller.importCsv(csv);
          if (format == 'db') await controller.restore(db);
          expect(controller.data.world.toJson(), expected, reason: format);
          expect(
            (await other.load()).world.toJson(),
            expected,
            reason: '$format disk',
          );
        } finally {
          controller.dispose();
          await other.close();
        }
      }
    },
  );

  test(
    'goal garden uses posted transfers; cosmetics cannot change money or analytics',
    () async {
      await c.saveGoal(
        const Goal(id: 'holiday', name: 'Отпуск', targetMinor: 10000),
      );
      FinanceEntry entry(
        String id,
        EntryKind kind,
        int amount, {
        String? goalId,
        String? category,
      }) => FinanceEntry(
        id: id,
        kind: kind,
        amountMinor: amount,
        currency: 'RUB',
        accountId: 'a',
        toGoalId: goalId,
        categoryId: category,
        date: now,
        memberId: 'me',
      );
      await c.saveEntry(
        entry('i', EntryKind.income, 10000, category: 'salary'),
      );
      await c.saveEntry(entry('e', EntryKind.expense, 2000, category: 'food'));
      await c.saveEntry(
        entry('t', EntryKind.transfer, 10000, goalId: 'holiday'),
      );
      expect(WorldPlant.of(c.data.goals.single, c.data.entries).stage, 4);
      expect(c.data.world.rewards, contains('goal_reward:1'));
      expect(c.data.world.memories, contains('goal:holiday'));
      final balance = c.balance;
      expect(balance, 108000);
      final totals = FinanceEngine.totals(
        c.data.entries,
        DateTime(2026, 11),
        DateTime(2026, 12),
        'RUB',
      );
      expect(totals.income, 10000);
      expect(totals.expense, 2000);
      final money = c.data.entries.map((e) => e.toJson()).toList();
      await c.purchaseWorldCosmetic('star');
      await c.configureWorld('pearl', {'right': 'star'});
      await c.saveWorldGame('constellation:0', [0, 1, 2, 3, 4]);
      await c.syncWorld();
      expect(c.balance, balance);
      expect(c.data.entries.map((e) => e.toJson()).toList(), money);
      await c.deleteEntry('t');
      expect(WorldPlant.of(c.data.goals.single, c.data.entries).stage, 0);
      expect(c.data.world.rewards, contains('goal_reward:1'));
      await c.deleteGoal('holiday');
      expect(c.data.world.memories, contains('goal:holiday'));
      await c.saveGoal(
        const Goal(
          id: 'holiday',
          name: 'Отпуск снова',
          targetMinor: 10000,
          savedMinor: 10000,
        ),
      );
      expect(
        c.data.world.rewards.keys
            .where((k) => k.startsWith('goal_reward:'))
            .length,
        1,
      );
    },
  );

  test(
    'corrupt reward import fails before changing the current ledger',
    () async {
      final backup =
          jsonDecode(await repo.exportJson()) as Map<String, dynamic>;
      final data = backup['data'] as Map<String, dynamic>;
      data['world'] = const WorldState().toJson();
      (data['world'] as Map)['rewards'] = {
        'tutorial': {
          'id': 'tutorial',
          'date': now.toIso8601String(),
          'xp': 999999,
          'sparks': 999999,
        },
      };
      final before = c.data.toJson();
      await expectLater(
        c.importJson(jsonEncode(backup)),
        throwsFormatException,
      );
      expect(c.data.toJson(), before);
      expect((await repo.load()).toJson(), before);
    },
  );
}
