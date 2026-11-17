import 'package:finora/data/demo_data.dart';
import 'package:finora/domain/duplicate_detector.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/detectors/recurring_detector.dart';
import 'package:finora/features/finora_ai/detectors/refund_detector.dart';
import 'package:finora/features/finora_ai/memory/personal_memory.dart';
import 'package:finora/features/finora_ai/models/ai_models.dart';
import 'package:finora/features/finora_ai/responses/intent_parser.dart';
import 'package:finora/features/finora_ai/responses/response_layer.dart';
import 'package:finora/features/finora_ai/services/ai_context.dart';
import 'package:finora/features/finora_ai/services/finora_ai_snapshot.dart';
import 'package:finora/features/finora_ai/services/smart_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finora AI, phase 3: what a regular payment is, subscriptions' costs,
/// dreams' outlook, the cushion and the stability index, refunds,
/// duplicates, safe daily spending, unusual months and smart notifications.
void main() {
  final now = DateTime(2026, 11, 20, 12);
  const groceries = 'expense-0', other = 'expense-10';
  var n = 0;
  FinanceEntry e(
    DateTime d,
    int rub,
    String? category, {
    String payee = '',
    EntryKind kind = EntryKind.expense,
    String account = 'card',
    String? toGoal,
    String note = '',
  }) => FinanceEntry(
    id: 'r${n++}',
    kind: kind,
    amountMinor: rub * 100,
    currency: 'RUB',
    accountId: account,
    categoryId: kind == EntryKind.transfer ? null : category,
    toGoalId: toGoal,
    payee: payee,
    note: note,
    date: d,
  );

  List<FinanceEntry> base() => [
    for (final m in [8, 9, 10]) ...[
      for (final day in [2, 6, 10, 14, 18, 22, 26])
        e(DateTime(2026, m, day), 1400, groceries, payee: 'Пятёрочка'),
      e(
        DateTime(2026, m, 10),
        100000,
        'income-0',
        payee: 'Зарплата',
        kind: EntryKind.income,
      ),
    ],
    for (final day in [2, 6, 10, 14, 18])
      e(DateTime(2026, 11, day), 1400, groceries, payee: 'Пятёрочка'),
    e(
      DateTime(2026, 11, 10),
      100000,
      'income-0',
      payee: 'Зарплата',
      kind: EntryKind.income,
    ),
  ];

  FinanceData data(
    List<FinanceEntry> entries, {
    List<Goal> goals = const [],
    List<Budget> budgets = const [],
    List<Account>? accounts,
  }) {
    final demo = createDemoData(now);
    return demo.copyWith(
      entries: entries,
      goals: goals,
      budgets: budgets,
      recurring: const [],
      accounts: accounts ?? demo.accounts,
      preferences: demo.preferences.copyWith(monthStart: 1),
    );
  }

  group('regular payments', () {
    test('rent, loans, utilities and transfers are not subscriptions', () {
      expect(RecurringDetector.natureOf('Аренда квартиры'), PaymentNature.rent);
      expect(RecurringDetector.natureOf('Сбер кредит'), PaymentNature.loan);
      expect(
        RecurringDetector.natureOf('Мосэнергосбыт'),
        PaymentNature.utilities,
      );
      expect(
        RecurringDetector.natureOf('Перевод маме'),
        PaymentNature.transfer,
      );
      // «газ» inside «магазин» is not gas.
      expect(RecurringDetector.natureOf('Магазин у дома'), PaymentNature.other);
      expect(
        RecurringDetector.natureOf('Netflix', knownService: true),
        PaymentNature.subscription,
      );
    });

    test('a steady monthly rent stays out of subscriptions', () {
      final entries = [
        ...base(),
        for (final m in [7, 8, 9, 10, 11])
          e(DateTime(2026, m, 1), 30000, other, payee: 'Аренда квартиры'),
      ];
      final found = RecurringDetector.detect(
        AiContext(data(entries), now: now),
      ).firstWhere((c) => c.displayName == 'Аренда квартиры');
      expect(found.nature, PaymentNature.rent);
      expect(found.subscriptionLikely, isFalse);
    });

    test('a subscription that stopped is listed as stopped', () {
      final entries = [
        ...base(),
        for (final m in [3, 4, 5, 6])
          e(DateTime(2026, m, 5), 299, other, payee: 'Кинопоиск'),
      ];
      final s = FinoraAiSnapshot.compute(data(entries), now: now);
      expect(
        s.subscriptionStats.stopped.map((c) => c.displayName),
        contains('Кинопоиск'),
      );
      // Not among the active ones.
      expect(s.recurring.any((c) => c.displayName == 'Кинопоиск'), isFalse);
      expect(
        ResponseLayer.subscriptionSummary(s),
        contains('больше не списывается'),
      );
    });
  });

  group('health', () {
    test('a dream: monthly and weekly need, pace and expected date', () {
      final goal = Goal(
        id: 'sea',
        name: 'Море',
        targetMinor: 12000000,
        deadline: DateTime(2027, 11, 20),
      );
      final entries = [
        ...base(),
        for (final m in [9, 10, 11])
          e(
            DateTime(2026, m, 12),
            5000,
            null,
            kind: EntryKind.transfer,
            toGoal: 'sea',
          ),
      ];
      final s = FinoraAiSnapshot.compute(
        data(entries, goals: [goal]),
        now: now,
      );
      final f = s.goalForecasts.single;
      expect(f.saved, 1500000);
      expect(f.monthlyPace, 500000);
      expect(f.monthlyNeed, isNotNull);
      expect(f.weeklyNeed, lessThan(f.monthlyNeed!));
      // 105 000 left at 5 000 a month: 21 months.
      expect(f.expectedDate, DateTime(2028, 8, 20));
      expect(f.deviation, lessThan(0));
      final text = ResponseLayer.insight(
        s,
        const Insight(kind: InsightKind.goal, priority: 0, subject: 'Море'),
      );
      expect(text, contains('не хватает'));
    });

    test('the cushion: savings against typical months', () {
      final accounts = [
        const Account(id: 'card', name: 'Карта'),
        const Account(
          id: 'save',
          name: 'Накопительный',
          type: 'savings',
          openingMinor: 2000000,
        ),
      ];
      final s = FinoraAiSnapshot.compute(
        data(base(), accounts: accounts),
        now: now,
      );
      final c = s.cushion!;
      expect(c.savings, 2000000);
      expect(c.monthlyExpenses, 980000);
      expect(c.months, closeTo(2.04, .01));
      expect(ResponseLayer.cushion(s), contains('2'));
    });

    test('the stability index adds up and explains itself', () {
      final s = FinoraAiSnapshot.compute(data(base()), now: now);
      final st = s.stability!;
      expect(st.max, 100);
      expect(st.score, inInclusiveRange(0, 100));
      expect(st.factors.map((f) => f.name), contains('Денежный поток'));
      final text = ResponseLayer.stability(s);
      expect(text, contains('не кредитный рейтинг'));
      // Too little history: no index.
      final fresh = FinoraAiSnapshot.compute(
        data([e(DateTime(2026, 11, 3), 500, groceries)]),
        now: now,
      );
      expect(fresh.stability, isNull);
    });

    test('a budget tells how much can be spent a day', () {
      const budget = Budget(
        id: 'g',
        name: 'Продукты',
        categoryId: groceries,
        limitMinor: 1000000,
      );
      final s = FinoraAiSnapshot.compute(
        data(base(), budgets: [budget]),
        now: now,
      );
      final r = s.risks.single;
      // 10 000 − 7 000 spent = 3 000 over 10 days left.
      expect(r.safeDaily, 30000);
    });
  });

  group('refunds and duplicates', () {
    test('money back is not income', () {
      final purchase = e(DateTime(2026, 11, 3), 5000, other, payee: 'Ozon');
      final back = e(
        DateTime(2026, 11, 8),
        5000,
        'income-0',
        payee: 'OZON.RU',
        kind: EntryKind.income,
      );
      final named = e(
        DateTime(2026, 11, 9),
        700,
        'income-0',
        payee: 'Магазин',
        note: 'возврат товара',
        kind: EntryKind.income,
      );
      final all = [...base(), purchase, back, named];
      expect(RefundDetector.matchOf(back, all)?.id, purchase.id);
      expect(RefundDetector.isRefund(named, all), isTrue);
      final ctx = AiContext(data(all), now: now);
      expect(ctx.refunds.map((x) => x.id), containsAll([back.id, named.id]));
      expect(ctx.incomes.any((x) => x.id == back.id), isFalse);
      // The salary stays income.
      expect(ctx.incomes.where((x) => x.payee == 'Зарплата'), hasLength(4));
    });

    test('a duplicate: same sum, account and place within a day', () {
      final first = e(DateTime(2026, 11, 3, 12), 450, groceries, payee: 'Кофе');
      final again = e(DateTime(2026, 11, 3, 18), 450, groceries, payee: 'кофе');
      final other = e(DateTime(2026, 11, 3, 18), 451, groceries, payee: 'Кофе');
      final later = e(DateTime(2026, 11, 6), 450, groceries, payee: 'Кофе');
      expect(DuplicateDetector.find(again, [first]), [first]);
      expect(DuplicateDetector.find(other, [first]), isEmpty);
      expect(DuplicateDetector.find(later, [first]), isEmpty);
    });
  });

  group('unusual months', () {
    test('an excluded month leaves the forecasts\' history', () {
      final ctx = AiContext(data(base()), now: now);
      expect(ctx.fullPeriodsWithData, [1, 2, 3]);
      final memory = PersonalMemory()..excludedMonths.add('2026-10');
      final s = FinoraAiSnapshot.compute(
        data(base()),
        now: now,
        memory: memory,
      );
      expect(s.ctx.fullPeriodsWithData, [2, 3]);
      final back = PersonalMemory.fromJson(memory.toJson());
      expect(back.excludedMonths, {'2026-10'});
    });
  });

  group('chat and notifications', () {
    test('new questions find their intents', () {
      expect(
        IntentParser.parse('Какие ближайшие платежи?').intent,
        AiIntent.payments,
      );
      expect(
        IntentParser.parse('На сколько хватит подушки?').intent,
        AiIntent.cushion,
      );
      expect(
        IntentParser.parse('Насколько стабильны мои финансы?').intent,
        AiIntent.stability,
      );
      // Older questions keep their meaning.
      expect(
        IntentParser.parse('Какие платежи повторяются?').intent,
        AiIntent.subscriptions,
      );
      expect(IntentParser.parse('Доходы стабильные?').intent, AiIntent.income);
    });

    test('smart notifications: the most important, once a day', () {
      final big = [
        ...base(),
        for (var i = 0; i < 6; i++)
          e(DateTime(2026, 10, 3 + i), 1000, other, payee: 'Техника'),
        e(DateTime(2026, 11, 19), 40000, other, payee: 'Техника'),
      ];
      final list = SmartNotifications.candidates(data(big), now: now);
      expect(list, isNotEmpty);
      final scores = [for (final c in list) c.priority];
      expect(scores, [...scores]..sort((a, b) => b.compareTo(a)));
      final first = SmartNotifications.pick(list, {}, now)!;
      // Already sent today: nothing more.
      expect(
        SmartNotifications.pick(list, {SmartNotifications.dayKey(now)}, now),
        isNull,
      );
      // The same fact is never sent twice.
      final next = SmartNotifications.pick(list, {first.key}, now);
      expect(next?.key, isNot(first.key));
      // Turned off in the AI settings: none.
      final off = data(big);
      expect(
        SmartNotifications.candidates(
          off.copyWith(
            preferences: off.preferences.copyWith(
              ai: const AiSettings(smartNotifications: false),
            ),
          ),
          now: now,
        ),
        isEmpty,
      );
    });
  });
}
