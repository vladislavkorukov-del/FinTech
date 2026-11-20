import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/planning/data_health.dart';
import 'package:finora/domain/planning/income_planner.dart';
import 'package:finora/domain/planning/journal.dart';
import 'package:finora/domain/planning/rules_engine.dart';
import 'package:finora/domain/planning/time_machine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 8: 100 000 operations — a save writes only what changed, and the
/// calculations stay fast. Timings are on the build machine (a phone is
/// slower); the bounds are generous.
void main() {
  sqfliteFfiInit();
  final now = DateTime(2026, 11, 20, 12);
  FinanceData big(int n) {
    final payees = [
      'Пятёрочка',
      'Магнит',
      'Такси',
      'Кофемания',
      'Аптека',
      'Ozon',
    ];
    return FinanceData(
      accounts: const [
        Account(id: 'card', name: 'Карта', openingMinor: 100000000),
      ],
      categories: const [
        Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
        Category(id: 'pay', name: 'Зарплата', kind: EntryKind.income),
      ],
      members: const [Member(id: 'me', name: 'Я')],
      entries: [
        for (var i = 0; i < n; i++)
          FinanceEntry(
            id: 'e$i',
            kind: i % 20 == 0 ? EntryKind.income : EntryKind.expense,
            amountMinor: 1000 + (i * 37) % 500000,
            currency: 'RUB',
            accountId: 'card',
            categoryId: i % 20 == 0 ? 'pay' : 'food',
            payee: payees[i % payees.length],
            date: now.subtract(Duration(minutes: i * 7)),
            tags: i % 50 == 0 ? const ['отпуск'] : const [],
          ),
      ],
    );
  }

  test('100 000 operations: incremental save, calculations', () async {
    final dir = await Directory.systemTemp.createTemp('finora-100k-');
    final repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/f.db',
    );
    var data = big(100000);
    final w = Stopwatch()..start();
    await repo.save(data);
    final full = w.elapsedMilliseconds;
    // One more operation: only it is written.
    w.reset();
    final one = FinanceEntry(
      id: 'new',
      kind: EntryKind.expense,
      amountMinor: 45000,
      currency: 'RUB',
      accountId: 'card',
      categoryId: 'food',
      date: now,
    );
    final next = Journal.stamp(
      data,
      data.copyWith(entries: [...data.entries, one]),
      now,
    );
    await repo.save(next);
    final incremental = w.elapsedMilliseconds;
    data = next;
    // A change and a removal.
    final edited = data.copyWith(
      entries: [
        for (final e in data.entries)
          if (e.id == 'e5')
            e.copyWith(amountMinor: 777)
          else if (e.id != 'e7')
            e,
      ],
    );
    await repo.save(edited);
    w.reset();
    final loaded = await repo.load();
    final load = w.elapsedMilliseconds;
    expect(loaded.entries, hasLength(100000));
    expect(loaded.entries.firstWhere((e) => e.id == 'e5').amountMinor, 777);
    expect(loaded.entries.any((e) => e.id == 'e7'), isFalse);
    expect(loaded.entries.firstWhere((e) => e.id == 'new').recordedAt, now);
    expect(loaded.entries.firstWhere((e) => e.id == 'e50').tags, ['отпуск']);
    // Calculations on 100 000.
    int time(void Function() f) {
      final s = Stopwatch()..start();
      f();
      return s.elapsedMilliseconds;
    }

    final t = {
      'balance': time(
        () => FinanceEngine.balance(loaded.accounts.first, loaded.entries),
      ),
      'totals': time(
        () => FinanceEngine.totals(
          loaded.entries,
          DateTime(2026, 11),
          DateTime(2026, 12),
          'RUB',
        ),
      ),
      'stamp': time(
        () => Journal.stamp(
          loaded,
          loaded.copyWith(entries: [...loaded.entries]),
          now,
        ),
      ),
      'diff': time(
        () => Journal.diff(
          loaded,
          loaded.copyWith(
            entries: [
              ...loaded.entries,
              one.copyWith(id: 'x'),
            ],
          ),
          now,
        ),
      ),
      'events': time(
        () => RulesEngine.events(
          loaded,
          loaded.copyWith(
            entries: [
              ...loaded.entries,
              one.copyWith(id: 'y'),
            ],
          ),
          now: now,
        ),
      ),
      'duplicates': time(() => DataHealth.findDuplicates(loaded.entries)),
      'income plan': time(() => IncomePlanner.plan(loaded, now: now)),
      'snapshot': time(() => PlanSnapshot.compute(loaded, now)),
    };
    // ignore: avoid_print
    print(
      '100k: full save ${full}ms, incremental $incremental ms, load ${load}ms, $t',
    );
    expect(incremental, lessThan(full));
    expect(incremental, lessThan(5000));
    for (final v in t.values) {
      expect(v, lessThan(3000));
    }
    await repo.close();
    await dir.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
