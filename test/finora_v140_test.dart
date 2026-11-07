import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/finora_outside.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late FinanceRepository repo;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('finora-v140-');
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/db',
    );
  });
  tearDown(() async {
    await repo.close();
    await temp.delete(recursive: true);
  });

  final now = DateTime.now();
  FinanceEntry e(
    String id,
    EntryKind kind,
    int sum, {
    DateTime? at,
    String? goal,
  }) => FinanceEntry(
    id: id,
    kind: kind,
    amountMinor: sum,
    currency: 'RUB',
    accountId: 'a',
    toGoalId: goal,
    categoryId: kind == EntryKind.income
        ? 'sal'
        : goal == null
        ? 'food'
        : null,
    date: at ?? now,
  );
  FinanceData data({
    List<FinanceEntry> entries = const [],
    List<Budget> budgets = const [],
    List<Goal> goals = const [],
  }) => FinanceData(
    accounts: const [Account(id: 'a', name: 'Карта', openingMinor: 100000000)],
    categories: const [
      Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
      Category(id: 'sal', name: 'Зарплата', kind: EntryKind.income),
    ],
    members: const [Member(id: 'me', name: 'Я')],
    entries: entries,
    budgets: budgets,
    goals: goals,
  );

  Future<String> tileFor(FinanceData d) async {
    await repo.save(d);
    final c = FinanceController(repo, _Quiet(), await repo.load());
    final t = FinoraOutside.tile(c, now: now);
    c.dispose();
    return t;
  }

  test('картинка виджета по данным', () async {
    expect(await tileFor(data()), 'check');
    // Over the budget → «Пополнить бюджет», with the overspend in the line.
    await repo.save(
      data(
        entries: [e('1', EntryKind.expense, 1200000)],
        budgets: const [
          Budget(id: 'b', name: 'Еда', limitMinor: 1000000, categoryId: 'food'),
        ],
      ),
    );
    final c = FinanceController(repo, _Quiet(), await repo.load());
    final (tile, line) = FinoraOutside.tileWithLine(c, now: now);
    expect(tile, 'budget_topup');
    expect(line, contains('Еда'));
    c.dispose();
    expect(
      await tileFor(data(entries: [e('1', EntryKind.income, 5000000)])),
      'income',
    );
    expect(
      await tileFor(
        data(
          entries: [e('1', EntryKind.expense, 950000)],
          budgets: const [
            Budget(
              id: 'b',
              name: 'Еда',
              limitMinor: 1000000,
              categoryId: 'food',
            ),
          ],
        ),
      ),
      'limit',
    );
    expect(
      await tileFor(
        data(
          goals: const [
            Goal(
              id: 'g',
              name: 'Отпуск',
              targetMinor: 1000000,
              savedMinor: 850000,
            ),
          ],
        ),
      ),
      'dream_savings',
    );
  });

  test('картинки лежат в ресурсах Android', () {
    for (final name in [
      'budget_month', 'budget_month_pink', 'budget_topup', 'calm', //
      'check', 'dream_savings', 'expenses_today', 'forward', //
      'goal_month', 'growing', 'income', 'income_tracking', 'limit', //
      'limit_today', 'pay_dont_forget', 'payment_reminder', //
      'payment_today', 'piggy', 'plan_budget', 'plus', //
      'record_due_blue', 'record_due_groceries', 'record_expense', //
      'record_expense_lilac', 'saving', //
    ]) {
      expect(
        File(
          'android/app/src/main/res/drawable-nodpi/finora_mood_$name.webp',
        ).existsSync(),
        isTrue,
        reason: name,
      );
    }
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('.FinoraWidgetSticker'),
    );
  });
}
