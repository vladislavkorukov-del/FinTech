import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/models.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late FinanceRepository repository;
  final now = DateTime(2026, 11, 4, 14);
  Future<FinanceRepository> reopen() => FinanceRepository.open(
    factory: databaseFactoryFfi,
    path: p.join(directory.path, 'ledger.db'),
    clock: () => now,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('finora-repository-');
    repository = await reopen();
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  test(
    'new profile defaults are dark coffee and notifications opt-in',
    () async {
      final data = await repository.load();
      expect(data.preferences.theme, 'dark');
      expect(data.preferences.accent, 'coffee');
      expect(data.preferences.notifications, isFalse);
      expect(data.recurring.every((r) => !r.reminderEnabled), isTrue);
      expect(data.preferences.toJson().containsKey('hideAmounts'), isFalse);
    },
  );

  test(
    'independent v2 fixture migrates to v3 preserving family media and explicit preferences',
    () async {
      final media = Directory(p.join(directory.path, 'receipts'));
      await media.create();
      final file = File(p.join(media.path, 'legacy.bin'));
      await file.writeAsBytes([1, 2, 3]);
      final path = p.join(directory.path, 'release-v2.db');
      final expected = await _createLegacyV1(
        path,
        now,
        version: 2,
        mediaPath: file.path,
      );
      final migrated = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: path,
        clock: () => now,
      );
      try {
        final actual = await migrated.load();
        expect(actual.toJson(), expected.toJson());
        expect(
          FinanceEngine.balance(actual.accounts.single, actual.entries),
          122457,
        );
        expect(actual.preferences.theme, 'system');
        expect(actual.preferences.notifications, isTrue);
        expect(actual.members.map((m) => m.name), ['Я', 'Семья']);
        expect(
          await File(actual.entries.single.attachmentPath!).readAsBytes(),
          [1, 2, 3],
        );
        expect(actual.recurring.every((r) => !r.reminderEnabled), isTrue);
        final reader = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        expect(await reader.getVersion(), FinanceRepository.schemaVersion);
        final preferences =
            jsonDecode(
                  (await reader.query(
                        'settings',
                        where: 'key = ?',
                        whereArgs: ['preferences'],
                      )).single['value']
                      as String,
                )
                as Map;
        expect(preferences.containsKey('hideAmounts'), isFalse);
        await reader.close();
        final archive = await migrated.exportJson();
        await repository.importJson(archive);
        expect(
          (await repository.load()).preferences.toJson(),
          expected.preferences.toJson(),
        );
      } finally {
        await migrated.close();
      }
      // Raw v2 snapshots are accepted without requiring a destructive upgrade.
      final original = p.join(directory.path, 'raw-v2.db');
      await _createLegacyV1(original, now, version: 2, mediaPath: file.path);
      await repository.restoreDatabase(original);
      expect((await repository.load()).toJson(), expected.toJson());
    },
  );

  test(
    'quick category preferences reopen, archive retains history and stale choices clear',
    () async {
      final data = await repository.load();
      final preferences = data.preferences.copyWith(
        lastExpenseCategoryId: 'expense-0',
        lastIncomeCategoryId: 'income-0',
      );
      await repository.save(data.copyWith(preferences: preferences));
      await repository.close();
      repository = await reopen();
      var actual = await repository.load();
      expect(actual.preferences.lastExpenseCategoryId, 'expense-0');
      expect(actual.preferences.lastIncomeCategoryId, 'income-0');
      final balance = FinanceEngine.totalBalance(
        actual.accounts,
        actual.entries,
        'RUB',
        actual.goals,
      );
      await repository.save(
        actual.copyWith(
          categories: [
            for (final c in actual.categories)
              c.id == 'expense-0' ? c.copyWith(archived: true) : c,
          ],
        ),
      );
      actual = await repository.load();
      expect(
        actual.categories.firstWhere((c) => c.id == 'expense-0').archived,
        isTrue,
      );
      expect(actual.entries.any((e) => e.categoryId == 'expense-0'), isTrue);
      expect(
        FinanceEngine.totalBalance(
          actual.accounts,
          actual.entries,
          'RUB',
          actual.goals,
        ),
        balance,
      );
      expect(actual.preferences.lastExpenseCategoryId, isNull);
      expect(actual.preferences.lastIncomeCategoryId, 'income-0');
      final archive =
          jsonDecode(await repository.exportJson()) as Map<String, dynamic>;
      archive['data']['preferences']['lastExpenseCategoryId'] = 'missing';
      archive['data']['preferences']['lastIncomeCategoryId'] = 'expense-1';
      await repository.importJson(jsonEncode(archive));
      actual = await repository.load();
      expect(actual.preferences.lastExpenseCategoryId, isNull);
      expect(actual.preferences.lastIncomeCategoryId, isNull);
    },
  );

  test(
    'reminder and service settings roundtrip independently and invalid values roll back',
    () async {
      final data = await repository.load();
      final rule = data.recurring.first.copyWith(
        serviceId: 'custom.internet',
        reminderEnabled: true,
        reminderDaysBefore: 7,
        reminderHour: 23,
        reminderMinute: 59,
        automatic: false,
        enabled: false,
      );
      await repository.save(data.copyWith(recurring: [rule]));
      await repository.close();
      repository = await reopen();
      final actual = await repository.load();
      expect(actual.recurring.single.toJson(), rule.toJson());
      final archive = await repository.exportJson();
      for (final invalid in [
        rule.copyWith(reminderDaysBefore: 2),
        rule.copyWith(reminderHour: 24),
        rule.copyWith(reminderMinute: -1),
        rule.copyWith(serviceId: '../escape'),
        rule.copyWith(serviceId: 'x' * 81),
      ]) {
        await expectLater(
          repository.save(actual.copyWith(recurring: [invalid])),
          throwsFormatException,
        );
        expect(await repository.exportJson(), archive);
      }
      for (final days in [0, 1, 3, 7]) {
        await repository.save(
          actual.copyWith(
            recurring: [
              rule.copyWith(
                reminderDaysBefore: days,
                enabled: true,
                automatic: true,
                reminderEnabled: false,
              ),
            ],
          ),
        );
      }
      await repository.importJson(archive);
      expect(
        (await repository.load()).recurring.single.toJson(),
        rule.toJson(),
      );
    },
  );

  test(
    'custom service icons embed restore and reject arbitrary imported paths',
    () async {
      final data = await repository.load();
      final root = Directory(p.join(directory.path, 'service_icons'));
      await root.create();
      final file = File(p.join(root.path, 'brand.bin'));
      await file.writeAsBytes([137, 80, 78, 71, 1, 2, 3]);
      final entry = data.entries.first.copyWith(
        serviceId: 'spotify',
        serviceIconPath: file.path,
      );
      final rule = data.recurring.first.copyWith(
        serviceId: 'custom.brand',
        customIconPath: file.path,
      );
      await repository.save(
        data.copyWith(
          entries: [entry, ...data.entries.skip(1)],
          recurring: [rule],
        ),
      );
      final archive = await repository.exportJson();
      expect(archive, isNot(contains(file.path)));
      final encoded = jsonDecode(archive) as Map<String, dynamic>;
      expect((encoded['serviceIcons'] as Map).keys.toSet(), {
        'entry:${entry.id}',
        'recurring:${rule.id}',
      });
      await file.delete();
      await repository.importJson(archive);
      var actual = await repository.load();
      expect(await File(actual.entries.first.serviceIconPath!).readAsBytes(), [
        137,
        80,
        78,
        71,
        1,
        2,
        3,
      ]);
      expect(
        await File(actual.recurring.single.customIconPath!).readAsBytes(),
        [137, 80, 78, 71, 1, 2, 3],
      );
      expect(await repository.exportJson(), archive);
      final snapshot = p.join(directory.path, 'service-icons.db');
      await repository.backupDatabase(snapshot);
      await repository.restoreDatabase(snapshot);
      actual = await repository.load();
      expect(actual.entries.first.serviceIconPath, isNotNull);
      expect(actual.recurring.single.customIconPath, isNotNull);
      final reader = await databaseFactoryFfi.openDatabase(
        snapshot,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await reader.update('entries', {'serviceIconPath': '/etc/passwd'});
      await reader.update('recurring', {'customIconPath': '../../secrets'});
      await reader.close();
      await repository.restoreDatabase(snapshot);
      actual = await repository.load();
      expect(actual.entries.every((e) => e.serviceIconPath == null), isTrue);
      expect(actual.recurring.single.customIconPath, isNull);
      await repository.importJson(archive);
      final saved = await repository.exportJson();
      encoded['serviceIcons'] = {
        'recurring:absent': base64Encode([1]),
      };
      await expectLater(
        repository.importJson(jsonEncode(encoded)),
        throwsFormatException,
      );
      expect(await repository.exportJson(), saved);
      encoded['serviceIcons'] = {};
      encoded['data']['entries'][0]['serviceIconPath'] = '/etc/passwd';
      encoded['data']['recurring'][0]['customIconPath'] = '../../secrets';
      await repository.importJson(jsonEncode(encoded));
      actual = await repository.load();
      expect(actual.entries.every((e) => e.serviceIconPath == null), isTrue);
      expect(actual.recurring.single.customIconPath, isNull);
    },
  );

  test(
    'v1 SQLite migration preserves records and classifies regular payments',
    () async {
      final legacyPath = p.join(directory.path, 'legacy.db');
      final expected = await _createLegacyV1(legacyPath, now);
      final migrated = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: legacyPath,
        clock: () => now,
      );
      try {
        final actual = await migrated.load();
        expect(actual.toJson(), expected.toJson());
        expect(
          FinanceEngine.balance(actual.accounts.single, actual.entries),
          122457,
        );
        expect(actual.entries.single.tags, ['Семья']);
        expect(
          actual.recurring.firstWhere((r) => r.id == 'legacy-sub').paymentType,
          'subscription',
        );
        expect(
          actual.recurring.firstWhere((r) => r.id == 'legacy-loan').paymentType,
          'mandatory',
        );
        // A second normal save exercises new destination FKs and both new columns.
        await migrated.save(actual);
        final reader = await databaseFactoryFfi.openDatabase(
          legacyPath,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        expect(await reader.getVersion(), FinanceRepository.schemaVersion);
        expect(await reader.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        await reader.close();
      } finally {
        await migrated.close();
      }
    },
  );

  test(
    'legacy JSON and raw database backups restore to v3 without lost balances',
    () async {
      final legacyPath = p.join(directory.path, 'legacy-restore.db');
      final expected = await _createLegacyV1(legacyPath, now);
      await repository.restoreDatabase(legacyPath);
      expect((await repository.load()).toJson(), expected.toJson());
      final oldData = expected.toJson();
      for (final e in oldData['entries'] as List) {
        (e as Map).remove('toGoalId');
      }
      for (final r in oldData['recurring'] as List) {
        (r as Map).remove('paymentType');
      }
      await repository.importJson(
        jsonEncode({'schemaVersion': 1, 'data': oldData}),
      );
      expect((await repository.load()).toJson(), expected.toJson());
      final newArchive =
          jsonDecode(await repository.exportJson()) as Map<String, dynamic>;
      expect(newArchive['schemaVersion'], 4);
      await repository.importJson(jsonEncode(newArchive));
      expect((await repository.load()).toJson(), expected.toJson());
      final newSnapshot = p.join(directory.path, 'migrated-snapshot.db');
      await repository.backupDatabase(newSnapshot);
      await repository.restoreDatabase(newSnapshot);
      expect((await repository.load()).toJson(), expected.toJson());
    },
  );

  test(
    'goal transfer edit delete undo and backup derive atomic balances',
    () async {
      final data = await repository.load();
      final account = data.accounts.first;
      final goal = data.goals.first;
      final balance = FinanceEngine.balance(account, data.entries);
      final wealth = FinanceEngine.totalBalance(
        data.accounts,
        data.entries,
        'RUB',
        data.goals,
      );
      final row = FinanceEntry(
        id: 'goal-funding',
        kind: EntryKind.transfer,
        amountMinor: 100000,
        currency: 'RUB',
        accountId: account.id,
        toGoalId: goal.id,
        date: now,
      );
      await repository.save(data.copyWith(entries: [...data.entries, row]));
      var actual = await repository.load();
      expect(FinanceEngine.balance(account, actual.entries), balance - 100000);
      expect(
        FinanceEngine.goalSaved(goal, actual.entries),
        goal.savedMinor + 100000,
      );
      expect(
        FinanceEngine.totalBalance(
          actual.accounts,
          actual.entries,
          'RUB',
          actual.goals,
        ),
        wealth,
      );
      final posted = actual;
      await repository.save(
        actual.copyWith(
          entries: [
            for (final e in actual.entries)
              e.id == row.id ? e.copyWith(amountMinor: 200000) : e,
          ],
        ),
      );
      actual = await repository.load();
      expect(FinanceEngine.balance(account, actual.entries), balance - 200000);
      expect(
        FinanceEngine.goalSaved(goal, actual.entries),
        goal.savedMinor + 200000,
      );
      await repository.save(data);
      actual = await repository.load();
      expect(FinanceEngine.goalSaved(goal, actual.entries), goal.savedMinor);
      expect(FinanceEngine.balance(account, actual.entries), balance);
      await repository.save(posted); // The same retained row implements undo.
      final archive = await repository.exportJson();
      await repository.save(data);
      await repository.importJson(archive);
      actual = await repository.load();
      expect(
        FinanceEngine.goalSaved(goal, actual.entries),
        goal.savedMinor + 100000,
      );
      final snapshot = p.join(directory.path, 'goal-snapshot.db');
      await repository.backupDatabase(snapshot);
      await repository.save(data);
      await repository.restoreDatabase(snapshot);
      expect(
        FinanceEngine.goalSaved(goal, (await repository.load()).entries),
        goal.savedMinor + 100000,
      );
      final before = await repository.exportJson();
      await expectLater(
        repository.save(actual.copyWith(goals: [])),
        throwsFormatException,
      );
      expect(await repository.exportJson(), before);
    },
  );

  test(
    'invalid goal destination and payment type are rejected without ledger change',
    () async {
      final data = await repository.load();
      final before = await repository.exportJson();
      final row = FinanceEntry(
        id: 'invalid',
        kind: EntryKind.transfer,
        amountMinor: 100,
        currency: 'RUB',
        accountId: data.accounts.first.id,
        toGoalId: data.goals.first.id,
        toAccountId: data.accounts.last.id,
        date: now,
      );
      await expectLater(
        repository.save(data.copyWith(entries: [...data.entries, row])),
        throwsFormatException,
      );
      await expectLater(
        repository.save(
          data.copyWith(
            recurring: [data.recurring.first.copyWith(paymentType: 'other')],
          ),
        ),
        throwsFormatException,
      );
      expect(await repository.exportJson(), before);
      for (final preset in [
        'lime',
        'electric',
        'sage',
        'graphite',
        'paper',
        'midnight',
        'gold',
        'lavender',
        'blue',
      ]) {
        await repository.save(
          data.copyWith(preferences: data.preferences.copyWith(accent: preset)),
        );
      }
    },
  );

  test(
    'clearing demo keeps goals referenced by personal contributions',
    () async {
      final data = await repository.load();
      final row = FinanceEntry(
        id: 'personal-funding',
        kind: EntryKind.transfer,
        amountMinor: 500,
        currency: 'RUB',
        accountId: data.accounts.first.id,
        toGoalId: data.goals.first.id,
        date: now,
      );
      await repository.save(data.copyWith(entries: [...data.entries, row]));
      await repository.clearDemo();
      final actual = await repository.load();
      expect(actual.goals.single.id, data.goals.first.id);
      expect(actual.goals.single.savedMinor, 0);
      expect(FinanceEngine.goalSaved(actual.goals.single, actual.entries), 500);
    },
  );

  test(
    'first launch seeds once, with full categories and two months',
    () async {
      final data = await repository.load();
      expect(data.demo, isTrue);
      expect(
        data.categories.where((c) => c.kind == EntryKind.expense).length,
        20,
      );
      expect(
        data.categories.where((c) => c.kind == EntryKind.income).length,
        8,
      );
      expect(
        data.entries.map((e) => e.date.month).toSet(),
        containsAll([10, 11]),
      );
      final count = data.entries.length;
      await repository.close();
      repository = await reopen();
      expect((await repository.load()).entries.length, count);
    },
  );

  test(
    'save and reopen preserves every model and relational metadata',
    () async {
      final data = await repository.load();
      final receipt = File(p.join(directory.path, 'receipt.jpg'));
      await receipt.writeAsBytes([1, 2, 3, 4]);
      final changed = data.copyWith(
        entries: [
          data.entries.first.copyWith(
            note: 'Семейные покупки\nВторая строка',
            tags: ['Дом', 'Важно'],
            latitude: 55.75,
            longitude: 37.62,
            attachmentPath: receipt.path,
          ),
          ...data.entries.skip(1),
        ],
        preferences: data.preferences.copyWith(
          theme: 'dark',
          lastExpenseCategoryId: 'expense-0',
        ),
      );
      await repository.save(changed);
      final before = jsonDecode(await repository.exportJson())['data'];
      await repository.close();
      repository = await reopen();
      final after = jsonDecode(await repository.exportJson())['data'];
      expect(after, before);
      expect((await repository.load()).entries.first.tags, ['Дом', 'Важно']);
    },
  );

  test(
    'transfer persists as one row and both balances change without expense',
    () async {
      final data = await repository.load();
      final source = data.accounts.first;
      final destination = data.accounts[1];
      final sourceBefore = FinanceEngine.balance(source, data.entries);
      final destinationBefore = FinanceEngine.balance(
        destination,
        data.entries,
      );
      final expensesBefore = FinanceEngine.totals(
        data.entries,
        DateTime(2026, 11),
        DateTime(2026, 12),
        'RUB',
      ).expense;
      final transfer = FinanceEntry(
        id: 'real-transfer',
        kind: EntryKind.transfer,
        amountMinor: 1000000,
        currency: 'RUB',
        accountId: source.id,
        toAccountId: destination.id,
        date: now,
      );
      await repository.save(
        data.copyWith(entries: [...data.entries, transfer]),
      );
      final saved = await repository.load();
      expect(
        FinanceEngine.balance(source, saved.entries),
        sourceBefore - 1000000,
      );
      expect(
        FinanceEngine.balance(destination, saved.entries),
        destinationBefore + 1000000,
      );
      expect(
        FinanceEngine.totals(
          saved.entries,
          DateTime(2026, 11),
          DateTime(2026, 12),
          'RUB',
        ).expense,
        expensesBefore,
      );
      expect(saved.entries.where((e) => e.id == transfer.id).length, 1);
    },
  );

  test('invalid import and failed save cannot erase existing data', () async {
    final original = await repository.exportJson();
    final envelope = jsonDecode(original) as Map<String, dynamic>;
    final data = envelope['data'] as Map<String, dynamic>;
    (data['entries'] as List).first['accountId'] = 'missing-account';
    await expectLater(
      repository.importJson(jsonEncode(envelope)),
      throwsFormatException,
    );
    expect(await repository.exportJson(), original);
    await expectLater(
      repository.importJson('{"schemaVersion":99,"data":{}}'),
      throwsFormatException,
    );
    expect(await repository.exportJson(), original);
    await expectLater(
      repository.importJson('{"schemaVersion":1,"data":{}}'),
      throwsFormatException,
    );
    expect(await repository.exportJson(), original);
    final current = await repository.load();
    await expectLater(
      repository.save(
        current.copyWith(
          accounts: [current.accounts.first, current.accounts.first],
        ),
      ),
      throwsFormatException,
    );
    expect(await repository.exportJson(), original);
  });

  test(
    'clear demo remains empty after reopening and keeps category catalogue',
    () async {
      await repository.clearDemo();
      await repository.close();
      repository = await reopen();
      final data = await repository.load();
      expect(data.demo, isFalse);
      expect(data.entries, isEmpty);
      expect(data.accounts, isEmpty);
      expect(data.categories.length, 28);
      expect(data.members.map((m) => m.id), contains('me'));
      await expectLater(repository.clearDemo(), throwsFormatException);
    },
  );

  test('clear demo preserves personal records made while exploring', () async {
    final data = await repository.load();
    final personal = FinanceEntry(
      id: 'personal-entry',
      kind: EntryKind.expense,
      amountMinor: 12000,
      currency: 'RUB',
      accountId: 'card',
      categoryId: 'expense-0',
      date: now,
    );
    const personalAccount = Account(
      id: 'personal-account',
      name: 'Моя карта',
      openingMinor: 50000,
    );
    await repository.save(
      data.copyWith(
        accounts: [...data.accounts, personalAccount],
        entries: [...data.entries, personal],
      ),
    );
    await repository.clearDemo();
    final remaining = await repository.load();
    expect(remaining.entries.map((e) => e.id), ['personal-entry']);
    expect(remaining.accounts.map((a) => a.id).toSet(), {
      'card',
      'personal-account',
    });
    expect(
      remaining.accounts.firstWhere((a) => a.id == 'card').openingMinor,
      0,
    );
    expect(
      remaining.accounts
          .firstWhere((a) => a.id == 'personal-account')
          .openingMinor,
      50000,
    );
  });

  test(
    'JSON export round trips and CSV escapes and neutralizes formulas',
    () async {
      final data = await repository.load();
      await repository.save(
        data.copyWith(
          entries: [
            data.entries.first.copyWith(
              payee: '=HYPERLINK("bad")',
              note: 'Чек, "спасибо"\nПокупки',
            ),
            ...data.entries.skip(1),
          ],
        ),
      );
      final original = await repository.exportJson();
      final csv = await repository.exportCsv();
      expect(csv, contains('"\'=HYPERLINK(""bad"")"'));
      expect(csv, contains('"Чек, ""спасибо""\nПокупки"'));
      await repository.clearDemo();
      await repository.importJson(original);
      expect(await repository.exportJson(), original);
    },
  );

  test(
    'portable JSON embeds receipt bytes, strips untrusted paths and rolls back invalid media',
    () async {
      final data = await repository.load();
      final file = File(p.join(directory.path, 'photo.jpg'));
      await file.writeAsBytes([255, 216, 255, 0, 8]);
      await repository.save(
        data.copyWith(
          entries: [
            data.entries.first.copyWith(attachmentPath: file.path),
            ...data.entries.skip(1),
          ],
        ),
      );
      final portable = await repository.exportJson();
      final envelope = jsonDecode(portable) as Map<String, dynamic>;
      expect(portable, isNot(contains(file.path)));
      await file.delete();
      await repository.importJson(portable);
      final imported = await repository.load();
      final restored = imported.entries.firstWhere(
        (e) => e.id == data.entries.first.id,
      );
      expect(await File(restored.attachmentPath!).readAsBytes(), [
        255,
        216,
        255,
        0,
        8,
      ]);
      expect(
        restored.attachmentPath,
        startsWith(p.join(directory.path, 'receipts')),
      );
      expect(await repository.exportJson(), portable);
      final before = await repository.exportJson();
      envelope['attachments'] = {
        'unknown-entry': base64Encode([1, 2]),
      };
      await expectLater(
        repository.importJson(jsonEncode(envelope)),
        throwsFormatException,
      );
      expect(await repository.exportJson(), before);
      envelope['attachments'] = {};
      (envelope['data']['entries'] as List).first['attachmentPath'] =
          '/etc/passwd';
      await repository.importJson(jsonEncode(envelope));
      expect(
        (await repository.load()).entries.every(
          (e) => e.attachmentPath == null,
        ),
        isTrue,
      );
    },
  );

  test(
    'invalid preference values and dates reject before changing ledger',
    () async {
      final before = await repository.exportJson();
      final data = await repository.load();
      await expectLater(
        repository.save(data.copyWith(members: [])),
        throwsFormatException,
      );
      for (final prefs in [
        data.preferences.copyWith(accent: 'unsupported'),
        data.preferences.copyWith(numberFormat: 'arbitrary'),
        data.preferences.copyWith(dateFormat: "unsupported'pattern"),
      ]) {
        await expectLater(
          repository.save(data.copyWith(preferences: prefs)),
          throwsFormatException,
        );
        expect(await repository.exportJson(), before);
      }
      await expectLater(
        repository.save(
          data.copyWith(
            goals: [data.goals.first.copyWith(deadline: DateTime(3000))],
          ),
        ),
        throwsFormatException,
      );
      await expectLater(
        repository.save(
          data.copyWith(
            recurring: [
              data.recurring.first.copyWith(nextDate: DateTime(1800)),
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(await repository.exportJson(), before);
      // Every value currently exposed by SettingsScreen is accepted.
      for (final accent in ['lime', 'gold', 'lavender', 'blue']) {
        await repository.save(
          data.copyWith(preferences: data.preferences.copyWith(accent: accent)),
        );
      }
      for (final format in ['dd.MM.yyyy', 'yyyy-MM-dd', 'dd/MM/yyyy']) {
        await repository.save(
          data.copyWith(
            preferences: data.preferences.copyWith(dateFormat: format),
          ),
        );
      }
    },
  );

  test(
    'JSON larger than 32 MiB round trips within the 50 MiB archive cap',
    () async {
      final data = await repository.load();
      final file = File(p.join(directory.path, 'large-receipt.bin'));
      await file.writeAsBytes(List<int>.filled(9 * 1024 * 1024, 127));
      await repository.save(
        data.copyWith(
          entries: [
            for (var i = 0; i < data.entries.length; i++)
              data.entries[i].copyWith(
                attachmentPath: i < 3 ? file.path : null,
              ),
          ],
        ),
      );
      final archive = await repository.exportJson();
      expect(utf8.encode(archive).length, greaterThan(32 * 1024 * 1024));
      expect(
        utf8.encode(archive).length,
        lessThan(FinanceRepository.maxBackupBytes),
      );
      await repository.importJson(archive);
      expect(await repository.exportJson(), archive);
    },
  );

  test(
    'raw restore ignores foreign receipt paths and keeps valid private files',
    () async {
      final data = await repository.load();
      final media = Directory(p.join(directory.path, 'receipts'));
      await media.create();
      final receipt = File(p.join(media.path, 'receipt.bin'));
      await receipt.writeAsBytes([1, 2, 3]);
      await repository.save(
        data.copyWith(
          entries: [
            data.entries.first.copyWith(attachmentPath: receipt.path),
            ...data.entries.skip(1),
          ],
        ),
      );
      final snapshot = p.join(directory.path, 'media.db');
      await repository.backupDatabase(snapshot);
      await repository.restoreDatabase(snapshot);
      expect(
        (await repository.load()).entries.first.attachmentPath,
        await receipt.resolveSymbolicLinks(),
      );
      final foreign = await databaseFactoryFfi.openDatabase(
        snapshot,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await foreign.update('attachments', {'path': '/etc/passwd'});
      await foreign.close();
      await repository.restoreDatabase(snapshot);
      expect(
        (await repository.load()).entries.every(
          (e) => e.attachmentPath == null,
        ),
        isTrue,
      );
      expect(await repository.exportJson(), isNot(contains('/etc/passwd')));
    },
  );

  test(
    'raw backup restores committed state and corrupt backup preserves live data',
    () async {
      final original = await repository.exportJson();
      final backupPath = p.join(directory.path, 'snapshot.db');
      expect(await repository.backupDatabase(backupPath), backupPath);
      expect(await File(backupPath).length(), greaterThan(0));
      await repository.clearDemo();
      await repository.restoreDatabase(backupPath);
      expect(await repository.exportJson(), original);
      final brokenPath = p.join(directory.path, 'broken.db');
      await File(brokenPath).writeAsString('not sqlite');
      await expectLater(
        repository.restoreDatabase(brokenPath),
        throwsFormatException,
      );
      expect(await repository.exportJson(), original);
      await expectLater(
        repository.backupDatabase(backupPath),
        throwsFormatException,
      );
    },
  );
}

/// An independent, populated release-v1 database fixture. It intentionally has
/// no toGoalId/paymentType columns and cannot be created by the v2 repository.
Future<FinanceData> _createLegacyV1(
  String path,
  DateTime now, {
  int version = 1,
  String? mediaPath,
}) async {
  final data = FinanceData(
    accounts: const [
      Account(id: 'legacy-account', name: 'Моя карта', openingMinor: 123456),
    ],
    categories: const [
      Category(
        id: 'legacy-sub-category',
        name: 'Подписки',
        kind: EntryKind.expense,
      ),
      Category(
        id: 'legacy-loan-category',
        name: 'Кредиты',
        kind: EntryKind.expense,
        order: 1,
      ),
    ],
    entries: [
      FinanceEntry(
        id: 'legacy-entry',
        kind: EntryKind.expense,
        amountMinor: 999,
        currency: 'RUB',
        accountId: 'legacy-account',
        categoryId: 'legacy-sub-category',
        date: now,
        note: 'Сохранить комментарий',
        attachmentPath: mediaPath,
        tags: const ['Семья'],
      ),
    ],
    budgets: const [
      Budget(id: 'legacy-budget', name: 'Все расходы', limitMinor: 150000),
    ],
    goals: const [
      Goal(
        id: 'legacy-goal',
        name: 'Резерв',
        targetMinor: 10000,
        savedMinor: 3000,
      ),
    ],
    recurring: [
      RecurringRule(
        id: 'legacy-sub',
        name: 'Сервис A',
        accountId: 'legacy-account',
        categoryId: 'legacy-sub-category',
        amountMinor: 999,
        nextDate: now.add(const Duration(days: 7)),
        paymentType: 'subscription',
      ),
      RecurringRule(
        id: 'legacy-loan',
        name: 'Ипотека',
        accountId: 'legacy-account',
        categoryId: 'legacy-loan-category',
        amountMinor: 100000,
        nextDate: now.add(const Duration(days: 9)),
        paymentType: 'mandatory',
      ),
    ],
    members: const [
      Member(id: 'me', name: 'Я'),
      Member(id: 'family', name: 'Семья'),
    ],
    preferences: const AppPreferences(
      theme: 'system',
      accent: 'gold',
      notifications: true,
    ),
  );
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys=ON');
      },
      onCreate: (db, _) async {
        for (final sql in version == 1 ? _v1Schema : _v2Schema) {
          await db.execute(sql);
        }
      },
    ),
  );
  Map<String, Object?> scalar(Map<String, Object?> row) => row.map(
    (key, value) => MapEntry(key, value is bool ? (value ? 1 : 0) : value),
  );
  await db.transaction((tx) async {
    await tx.insert('currencies', {'code': 'RUB', 'minorDigits': 2});
    await tx.insert('accounts', scalar(data.accounts.single.toJson()));
    for (final member in data.members) {
      await tx.insert('members', member.toJson());
    }
    for (final c in data.categories) {
      await tx.insert(
        'categories',
        c.toJson()
          ..remove('subcategories')
          ..remove('archived'),
      );
    }
    await tx.insert('goals', data.goals.single.toJson());
    final row = data.entries.single.toJson()
      ..remove('toGoalId')
      ..remove('serviceId')
      ..remove('serviceIconPath')
      ..remove('attachmentPath')
      ..remove('tags');
    if (version == 2) {
      row['toGoalId'] = null;
    }
    await tx.insert('entries', row);
    if (mediaPath != null) {
      await tx.insert('attachments', {
        'entryId': 'legacy-entry',
        'path': mediaPath,
      });
    }
    await tx.insert('tags', {'id': 1, 'name': 'Семья'});
    await tx.insert('entry_tags', {
      'entryId': 'legacy-entry',
      'tagId': 1,
      'position': 0,
    });
    await tx.insert('budgets', data.budgets.single.toJson());
    for (final r in data.recurring) {
      final row = scalar(
        r.toJson()
          ..remove('paymentType')
          ..remove('serviceId')
          ..remove('customIconPath')
          ..remove('reminderEnabled')
          ..remove('reminderDaysBefore')
          ..remove('reminderHour')
          ..remove('reminderMinute')
          ..remove('icon')
          ..remove('color'),
      );
      if (version == 2) {
        row['paymentType'] = r.paymentType;
      }
      await tx.insert('recurring', row);
    }
    await tx.insert('settings', {'key': 'initialized', 'value': 'true'});
    await tx.insert('settings', {'key': 'demo', 'value': 'false'});
    await tx.insert('settings', {
      'key': 'preferences',
      'value': jsonEncode({...data.preferences.toJson(), 'hideAmounts': true}),
    });
  });
  await db.close();
  return data;
}

const _v1Schema = [
  'CREATE TABLE currencies(code TEXT PRIMARY KEY, minorDigits INTEGER NOT NULL)',
  'CREATE TABLE members(id TEXT PRIMARY KEY, name TEXT NOT NULL)',
  'CREATE TABLE accounts(id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, currency TEXT NOT NULL REFERENCES currencies(code), bank TEXT NOT NULL, lastFour TEXT NOT NULL, openingMinor INTEGER NOT NULL, creditLimitMinor INTEGER NOT NULL, excluded INTEGER NOT NULL, archived INTEGER NOT NULL, color INTEGER NOT NULL, icon INTEGER NOT NULL)',
  'CREATE TABLE categories(id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, color INTEGER NOT NULL, background INTEGER NOT NULL, icon INTEGER NOT NULL, "order" INTEGER NOT NULL)',
  'CREATE TABLE subcategories(categoryId TEXT NOT NULL REFERENCES categories(id), name TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY(categoryId,name))',
  'CREATE TABLE entries(id TEXT PRIMARY KEY, kind TEXT NOT NULL, amountMinor INTEGER NOT NULL CHECK(amountMinor > 0), currency TEXT NOT NULL REFERENCES currencies(code), accountId TEXT NOT NULL REFERENCES accounts(id), toAccountId TEXT REFERENCES accounts(id), categoryId TEXT REFERENCES categories(id), subcategory TEXT, destinationMinor INTEGER, date TEXT NOT NULL, note TEXT NOT NULL, payee TEXT NOT NULL, status TEXT NOT NULL, recurrence TEXT NOT NULL, memberId TEXT NOT NULL REFERENCES members(id), latitude REAL, longitude REAL)',
  'CREATE INDEX entries_date ON entries(date)',
  'CREATE INDEX entries_account ON entries(accountId)',
  'CREATE INDEX entries_category ON entries(categoryId)',
  'CREATE TABLE tags(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE)',
  'CREATE TABLE entry_tags(entryId TEXT NOT NULL REFERENCES entries(id), tagId INTEGER NOT NULL REFERENCES tags(id), position INTEGER NOT NULL, PRIMARY KEY(entryId,tagId))',
  'CREATE TABLE attachments(entryId TEXT PRIMARY KEY REFERENCES entries(id), path TEXT NOT NULL)',
  'CREATE TABLE budgets(id TEXT PRIMARY KEY, name TEXT NOT NULL, currency TEXT NOT NULL REFERENCES currencies(code), categoryId TEXT REFERENCES categories(id), limitMinor INTEGER NOT NULL CHECK(limitMinor > 0))',
  'CREATE TABLE goals(id TEXT PRIMARY KEY, name TEXT NOT NULL, currency TEXT NOT NULL REFERENCES currencies(code), targetMinor INTEGER NOT NULL CHECK(targetMinor > 0), savedMinor INTEGER NOT NULL CHECK(savedMinor >= 0), color INTEGER NOT NULL, icon INTEGER NOT NULL, deadline TEXT)',
  'CREATE TABLE recurring(id TEXT PRIMARY KEY, name TEXT NOT NULL, accountId TEXT NOT NULL REFERENCES accounts(id), currency TEXT NOT NULL REFERENCES currencies(code), categoryId TEXT REFERENCES categories(id), kind TEXT NOT NULL, amountMinor INTEGER NOT NULL CHECK(amountMinor > 0), interval INTEGER NOT NULL, anchorDay INTEGER NOT NULL, frequency TEXT NOT NULL, nextDate TEXT NOT NULL, automatic INTEGER NOT NULL, enabled INTEGER NOT NULL)',
  'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
];

const _v2Schema = [
  'CREATE TABLE currencies(code TEXT PRIMARY KEY, minorDigits INTEGER NOT NULL)',
  'CREATE TABLE members(id TEXT PRIMARY KEY, name TEXT NOT NULL)',
  'CREATE TABLE accounts(id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, currency TEXT NOT NULL REFERENCES currencies(code), bank TEXT NOT NULL, lastFour TEXT NOT NULL, openingMinor INTEGER NOT NULL, creditLimitMinor INTEGER NOT NULL, excluded INTEGER NOT NULL, archived INTEGER NOT NULL, color INTEGER NOT NULL, icon INTEGER NOT NULL)',
  'CREATE TABLE categories(id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, color INTEGER NOT NULL, background INTEGER NOT NULL, icon INTEGER NOT NULL, "order" INTEGER NOT NULL)',
  'CREATE TABLE subcategories(categoryId TEXT NOT NULL REFERENCES categories(id), name TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY(categoryId,name))',
  'CREATE TABLE entries(id TEXT PRIMARY KEY, kind TEXT NOT NULL, amountMinor INTEGER NOT NULL CHECK(amountMinor > 0), currency TEXT NOT NULL REFERENCES currencies(code), accountId TEXT NOT NULL REFERENCES accounts(id), toAccountId TEXT REFERENCES accounts(id), toGoalId TEXT REFERENCES goals(id), categoryId TEXT REFERENCES categories(id), subcategory TEXT, destinationMinor INTEGER, date TEXT NOT NULL, note TEXT NOT NULL, payee TEXT NOT NULL, status TEXT NOT NULL, recurrence TEXT NOT NULL, memberId TEXT NOT NULL REFERENCES members(id), latitude REAL, longitude REAL)',
  'CREATE INDEX entries_date ON entries(date)',
  'CREATE INDEX entries_account ON entries(accountId)',
  'CREATE INDEX entries_category ON entries(categoryId)',
  'CREATE INDEX entries_goal ON entries(toGoalId)',
  'CREATE TABLE tags(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE)',
  'CREATE TABLE entry_tags(entryId TEXT NOT NULL REFERENCES entries(id), tagId INTEGER NOT NULL REFERENCES tags(id), position INTEGER NOT NULL, PRIMARY KEY(entryId,tagId))',
  'CREATE TABLE attachments(entryId TEXT PRIMARY KEY REFERENCES entries(id), path TEXT NOT NULL)',
  'CREATE TABLE budgets(id TEXT PRIMARY KEY, name TEXT NOT NULL, currency TEXT NOT NULL REFERENCES currencies(code), categoryId TEXT REFERENCES categories(id), limitMinor INTEGER NOT NULL CHECK(limitMinor > 0))',
  'CREATE TABLE goals(id TEXT PRIMARY KEY, name TEXT NOT NULL, currency TEXT NOT NULL REFERENCES currencies(code), targetMinor INTEGER NOT NULL CHECK(targetMinor > 0), savedMinor INTEGER NOT NULL CHECK(savedMinor >= 0), color INTEGER NOT NULL, icon INTEGER NOT NULL, deadline TEXT)',
  'CREATE TABLE recurring(id TEXT PRIMARY KEY, name TEXT NOT NULL, accountId TEXT NOT NULL REFERENCES accounts(id), currency TEXT NOT NULL REFERENCES currencies(code), categoryId TEXT REFERENCES categories(id), kind TEXT NOT NULL, amountMinor INTEGER NOT NULL CHECK(amountMinor > 0), interval INTEGER NOT NULL, anchorDay INTEGER NOT NULL, frequency TEXT NOT NULL, nextDate TEXT NOT NULL, automatic INTEGER NOT NULL, enabled INTEGER NOT NULL, paymentType TEXT NOT NULL DEFAULT \'mandatory\')',
  'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
];
