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
          hideAmounts: true,
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
