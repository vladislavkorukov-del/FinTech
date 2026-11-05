import 'dart:io';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/scan_document.dart';
import 'package:finora/domain/scan_draft.dart';
import 'package:finora/domain/scan_import.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  sqfliteFfiInit();
  const fixture = FinanceData(
    accounts: [
      Account(id: 'card', name: 'Карта', openingMinor: 1000000),
      Account(id: 'cash', name: 'Наличные'),
      Account(id: 'usd', name: 'USD', currency: 'USD'),
      Account(id: 'archive', name: 'Архив', archived: true),
    ],
    categories: [
      Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
      Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
      Category(
        id: 'archive',
        name: 'Архив',
        kind: EntryKind.expense,
        archived: true,
      ),
    ],
    members: [Member(id: 'me', name: 'Я')],
    demo: false,
  );
  ScanDraft draft({
    EntryKind kind = EntryKind.expense,
    int amount = 24480,
    String? category = 'food',
    String currency = 'RUB',
    String merchant = 'Пятёрочка',
  }) => ScanDraft(
    rawText: 'bank line',
    amountMinor: amount,
    currency: currency,
    payee: merchant,
    date: DateTime(2026, 11, 5),
    kind: kind,
    categoryId: category,
  );
  test(
    'batch preparation matches currency, skips existing possible repeats, preserves repeated legitimate new rows',
    () {
      final d = draft();
      final saved = ScanImport.entries(
        [ScanImportItem(draft: d, accountId: 'card')],
        fixture,
        newId: () => 'old',
      ).single;
      final data = fixture.copyWith(entries: [saved]);
      final result = ScanImport.prepare(
        ScanDocument(
          drafts: [
            d,
            d,
            draft(currency: 'USD'),
          ],
        ),
        data,
        preferredAccountId: 'card',
      );
      expect(result.map((i) => i.selected), [false, false, true]);
      expect(result.last.accountId, 'usd');
      final fresh = ScanImport.prepare(
        ScanDocument(drafts: [d, d]),
        fixture,
        preferredAccountId: 'card',
      );
      var index = 0;
      final entries = ScanImport.entries(
        fresh,
        fixture,
        newId: () => '${index++}',
      );
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.amountMinor), [24480, 24480]);
    },
  );
  test(
    'entire batch rejects missing amount, wrong currency, archived category or unresolved transfer',
    () {
      final valid = ScanImportItem(draft: draft(), accountId: 'card');
      for (final invalid in [
        valid.copyWith(draft: draft().copyWith(amountMinor: null)),
        valid.copyWith(draft: draft().copyWith(kind: null)),
        valid.copyWith(draft: draft(currency: 'USD')),
        valid.copyWith(draft: draft(category: 'archive')),
        valid.copyWith(accountId: 'archive'),
        valid.copyWith(draft: draft(kind: EntryKind.transfer, category: null)),
      ]) {
        expect(
          () => ScanImport.entries(
            [valid, invalid],
            fixture,
            newId: () => 'test',
          ),
          throwsFormatException,
        );
      }
      expect(fixture.entries, isEmpty);
    },
  );
  test(
    'transfer imports balance both accounts and stay outside income/expense statistics',
    () {
      final entries = ScanImport.entries(
        [
          ScanImportItem(
            draft: draft(
              kind: EntryKind.transfer,
              category: null,
              amount: 100000,
            ),
            accountId: 'card',
            toAccountId: 'cash',
          ),
        ],
        fixture,
        newId: () => 'transfer',
      );
      expect(FinanceEngine.balance(fixture.accounts[0], entries), 900000);
      expect(FinanceEngine.balance(fixture.accounts[1], entries), 100000);
      final totals = FinanceEngine.totals(
        entries,
        DateTime(2026, 11),
        DateTime(2026, 12),
        'RUB',
      );
      expect(totals.income, 0);
      expect(totals.expense, 0);
      expect(entries.single.categoryId, isNull);
    },
  );
  test(
    'SQLite imports selected entries atomically, persists on reopen and does not replace family data',
    () async {
      final dir = await Directory.systemTemp.createTemp('finance-scan-batch-');
      var repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/ledger',
      );
      await repo.save(fixture);
      final controller = FinanceController(repo, _Quiet(), await repo.load());
      final items = [
        ScanImportItem(draft: draft(), accountId: 'card'),
        ScanImportItem(
          draft: draft(
            kind: EntryKind.income,
            category: 'salary',
            amount: 8900000,
            merchant: 'Зарплата',
          ),
          accountId: 'card',
        ),
        ScanImportItem(
          draft: draft(amount: 99999),
          accountId: 'card',
          selected: false,
        ),
      ];
      await controller.importScanned(
        items,
        attachmentPath: '${dir.path}/receipts/source.png',
      );
      expect(controller.data.entries, hasLength(2));
      expect(controller.data.preferences.lastExpenseCategoryId, 'food');
      expect(controller.data.preferences.lastIncomeCategoryId, 'salary');
      expect(
        controller.data.members.map((m) => m.toJson()).toList(),
        fixture.members.map((m) => m.toJson()).toList(),
      );
      expect(
        FinanceEngine.balance(fixture.accounts.first, controller.data.entries),
        9875520,
      );
      final snapshot = controller.data.toJson();
      await expectLater(
        controller.importScanned([
          items.first,
          items.last.copyWith(
            selected: true,
            draft: items.last.draft.copyWith(categoryId: null),
          ),
        ]),
        throwsFormatException,
      );
      expect(controller.data.toJson(), snapshot);
      final persisted = await repo.load();
      expect(
        {for (final e in persisted.entries) e.id: e.toJson()},
        {for (final e in controller.data.entries) e.id: e.toJson()},
      );
      expect(
        persisted.toJson()..remove('entries'),
        controller.data.toJson()..remove('entries'),
      );
      controller.dispose();
      await repo.close();
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/ledger',
      );
      expect((await repo.load()).entries, hasLength(2));
      await repo.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'failed SQLite commit leaves ledger and learned category untouched',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'finance-scan-failure-',
      );
      final repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/ledger',
      );
      await repo.save(fixture);
      final controller = FinanceController(repo, _Quiet(), await repo.load());
      final snapshot = controller.data.toJson();
      await repo.close();
      await expectLater(
        controller.importScanned([
          ScanImportItem(draft: draft(), accountId: 'card'),
        ]),
        throwsA(anything),
      );
      expect(controller.data.toJson(), snapshot);
      controller.dispose();
      await dir.delete(recursive: true);
    },
  );
}
