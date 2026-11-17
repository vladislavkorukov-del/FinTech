import 'package:finora/data/demo_data.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/detectors/anomaly_detector.dart';
import 'package:finora/features/finora_ai/detectors/recurring_detector.dart';
import 'package:finora/features/finora_ai/insights/insight_engine.dart';
import 'package:finora/features/finora_ai/insights/month_comparison_engine.dart';
import 'package:finora/features/finora_ai/memory/personal_memory.dart';
import 'package:finora/features/finora_ai/models/ai_models.dart';
import 'package:finora/features/finora_ai/responses/capabilities.dart';
import 'package:finora/features/finora_ai/responses/intent_parser.dart';
import 'package:finora/features/finora_ai/responses/response_layer.dart';
import 'package:finora/features/finora_ai/services/finora_ai.dart';
import 'package:finora/features/finora_ai/services/ai_context.dart';
import 'package:finora/features/finora_ai/services/finora_ai_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finora AI, phase 1: traceable insights, any-period comparisons, more
/// rhythms of regular payments, person-relative anomalies and the cash-flow
/// timeline.
void main() {
  // Friday.
  final now = DateTime(2026, 11, 20, 12);
  const groceries = 'expense-0', cafe = 'expense-1', other = 'expense-10';
  var n = 0;
  FinanceEntry e(
    DateTime d,
    int rub,
    String category, {
    String payee = '',
    EntryKind kind = EntryKind.expense,
  }) => FinanceEntry(
    id: 'p${n++}',
    kind: kind,
    amountMinor: rub * 100,
    currency: 'RUB',
    accountId: 'card',
    categoryId: category,
    payee: payee,
    date: d,
  );

  List<FinanceEntry> base() => [
    for (final m in [8, 9, 10]) ...[
      for (final day in [2, 6, 10, 14, 18, 22, 26])
        e(DateTime(2026, m, day), 1400, groceries, payee: 'Пятёрочка'),
      for (final day in [3, 9, 15, 21])
        e(DateTime(2026, m, day), 1000, cafe, payee: 'Шоколадница'),
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
    for (final day in [3, 9, 15])
      e(DateTime(2026, 11, day), 1000, cafe, payee: 'Шоколадница'),
    e(
      DateTime(2026, 11, 10),
      100000,
      'income-0',
      payee: 'Зарплата',
      kind: EntryKind.income,
    ),
  ];

  FinanceData data(List<FinanceEntry> entries, {bool rent = true}) {
    final demo = createDemoData(now);
    return demo.copyWith(
      entries: entries,
      budgets: const [],
      goals: const [],
      recurring: [
        if (rent)
          RecurringRule(
            id: 'rent',
            name: 'Аренда',
            accountId: 'card',
            currency: 'RUB',
            categoryId: 'expense-4',
            kind: EntryKind.expense,
            amountMinor: 3000000,
            interval: 1,
            frequency: 'monthly',
            paymentType: 'mandatory',
            nextDate: DateTime(2026, 11, 25),
            anchorDay: 25,
          ),
      ],
      preferences: demo.preferences.copyWith(monthStart: 1, weekStart: 1),
    );
  }

  group('period comparison', () {
    test('month: fair days, income and cash flow', () {
      final s = FinoraAiSnapshot.compute(data(base()), now: now);
      final c = s.compare(PeriodUnit.month);
      expect(c.currentStart, DateTime(2026, 11));
      expect(c.previousStart, DateTime(2026, 10));
      // 20 days of November against the first 20 days of October.
      expect(c.previousEnd, DateTime(2026, 10, 21));
      expect(c.expense, s.comparison.current);
      expect(c.income, 10000000);
      expect(c.previousIncome, 10000000);
      expect(c.cashflow, c.income - c.expense);
      expect(c.insufficient, isNull);
    });

    test('day, week, quarter and year bounds', () {
      final ctx = AiContext(data(base()), now: now);
      PeriodComparison of(PeriodUnit u) =>
          MonthComparisonEngine.comparePeriods(ctx, unit: u);
      expect(of(PeriodUnit.day).currentStart, DateTime(2026, 11, 20));
      expect(of(PeriodUnit.day).previousStart, DateTime(2026, 11, 19));
      // The week starts on Monday (preference 1).
      expect(of(PeriodUnit.week).currentStart, DateTime(2026, 11, 16));
      expect(of(PeriodUnit.week).previousStart, DateTime(2026, 11, 9));
      expect(of(PeriodUnit.quarter).currentStart, DateTime(2026, 10));
      expect(of(PeriodUnit.quarter).previousStart, DateTime(2026, 7));
      expect(of(PeriodUnit.year).currentStart, DateTime(2026));
      expect(of(PeriodUnit.year).previousStart, DateTime(2025));
    });

    test('a custom range is compared with the same length before it', () {
      final ctx = AiContext(data(base()), now: now);
      final c = MonthComparisonEngine.comparePeriods(
        ctx,
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 11),
      );
      expect(c.unit, isNull);
      expect(c.previousStart, DateTime(2026, 10, 22));
      expect(c.previousEnd, DateTime(2026, 11, 1));
    });

    test('nothing before: insufficient, no made-up percent', () {
      final ctx = AiContext(
        data([e(DateTime(2026, 11, 3), 500, cafe)]),
        now: now,
      );
      final c = MonthComparisonEngine.comparePeriods(
        ctx,
        unit: PeriodUnit.month,
      );
      expect(c.insufficient, InsufficientData.noPreviousData);
      expect(c.expensePercent, isNull);
    });
  });

  group('regular payments', () {
    test('quarterly and every-two-weeks rhythms', () {
      final entries = [
        ...base(),
        for (final d in [
          DateTime(2026, 2, 12),
          DateTime(2026, 5, 12),
          DateTime(2026, 8, 12),
          DateTime(2026, 11, 12),
        ])
          e(d, 4500, other, payee: 'Страховка'),
        for (
          var d = DateTime(2026, 8, 7);
          d.isBefore(now);
          d = d.add(const Duration(days: 14))
        )
          e(d, 700, other, payee: 'Клининг'),
      ];
      final found = RecurringDetector.detect(
        AiContext(data(entries), now: now),
      );
      Cadence? of(String name) =>
          found.where((c) => c.displayName == name).firstOrNull?.cadence;
      expect(of('Страховка'), Cadence.quarterly);
      expect(of('Клининг'), Cadence.biweekly);
    });

    test('a salary is a regular income, never a subscription', () {
      final found = RecurringDetector.detect(
        AiContext(data(base()), now: now),
        kind: EntryKind.income,
      );
      final salary = found.single;
      expect(salary.displayName, 'Зарплата');
      expect(salary.kind, EntryKind.income);
      expect(salary.cadence, Cadence.monthly);
      expect(salary.subscriptionLikely, isFalse);
    });

    test('a changed price of a subscription is noticed', () {
      final entries = [
        ...base(),
        for (final m in [7, 8, 9, 10])
          e(DateTime(2026, m, 5), 169, other, payee: 'Spotify'),
        e(DateTime(2026, 11, 5), 199, other, payee: 'Spotify'),
      ];
      final spotify = RecurringDetector.detect(
        AiContext(data(entries), now: now),
      ).firstWhere((c) => c.displayName == 'Spotify');
      expect(spotify.typicalAmount, 16900);
      expect(spotify.lastAmount, 19900);
      expect(spotify.amountChanged, isTrue);
    });

    test('a payment that usually has happened by now is «late»', () {
      final entries = [
        ...base(),
        for (final m in [7, 8, 9, 10])
          e(DateTime(2026, m, 5), 169, other, payee: 'Spotify'),
      ];
      final s = FinoraAiSnapshot.compute(data(entries), now: now);
      final late = s.timeline.late.where((e) => e.title == 'Spotify');
      expect(late, hasLength(1));
      final insight = s.insights.firstWhere(
        (i) => i.kind == InsightKind.latePayment,
      );
      final text = ResponseLayer.insight(s, insight);
      expect(text, contains('уже проходил'));
      // Never says the person forgot to pay.
      expect(text.toLowerCase(), isNot(contains('забыл')));
    });
  });

  group('anomalies', () {
    test('compared with the same place when there is enough history', () {
      final entries = [
        ...base(),
        for (final day in [4, 8, 12, 16, 20])
          for (final m in [9, 10])
            e(DateTime(2026, m, day), 300, groceries, payee: 'ВкусВилл'),
        e(DateTime(2026, 11, 17), 1200, groceries, payee: 'ВкусВилл'),
      ];
      final a = AnomalyDetector.detect(
        AiContext(data(entries), now: now),
      ).single;
      expect(a.entry.payee, 'ВкусВилл');
      expect(a.basis, AnomalyBasis.merchant);
      expect(a.typical, 30000);
      expect(a.history, 10);
    });

    test('many more operations than usual by this day', () {
      final entries = [
        ...base(),
        for (var i = 0; i < 30; i++)
          e(DateTime(2026, 11, 1 + i % 19), 200, cafe, payee: 'Кофейня'),
      ];
      final f = AnomalyDetector.frequency(AiContext(data(entries), now: now));
      expect(f, isNotNull);
      expect(f!.count, greaterThan(f.typical));
    });

    test('a usual month has no frequency anomaly', () {
      expect(
        AnomalyDetector.frequency(AiContext(data(base()), now: now)),
        isNull,
      );
    });
  });

  group('insights', () {
    test('every insight is traceable and ranked by relevance', () {
      final s = FinoraAiSnapshot.compute(data(base()), now: now);
      expect(s.insights, isNotEmpty);
      for (final i in s.insights) {
        expect(i.trace, isNotNull, reason: i.kind.name);
        expect(i.trace!.sourceEngine, isNotEmpty);
        expect(i.trace!.periodStart, DateTime(2026, 11));
        expect(i.confidence, inInclusiveRange(InsightEngine.minConfidence, 1));
      }
      final scores = [for (final i in s.insights) i.relevance];
      expect(scores, [...scores]..sort((a, b) => b.compareTo(a)));
      expect(s.top.length, lessThanOrEqualTo(InsightEngine.topCount));
      expect(s.top.any((i) => i.kind == InsightKind.summary), isFalse);
    });

    test('one insight per fact; weak and snoozed ones are left out', () {
      final memory = PersonalMemory()
        ..snooze('trend:x', now: now)
        ..snooze('growth:a', now: now);
      const weak = Insight(
        kind: InsightKind.habit,
        priority: 99,
        confidence: .2,
      );
      final ranked = InsightEngine.rank(
        const [
          Insight(kind: InsightKind.growth, priority: 70, categoryId: 'b'),
          Insight(kind: InsightKind.growth, priority: 40, categoryId: 'b'),
          Insight(kind: InsightKind.growth, priority: 70, categoryId: 'a'),
          weak,
        ],
        memory: memory,
        now: now,
      );
      expect(ranked, hasLength(1));
      expect(ranked.single.priority, 70);
      expect(ranked.single.categoryId, 'b');
      // The cooldown ends.
      expect(
        memory.isSnoozed('growth:a', now.add(const Duration(days: 8))),
        isFalse,
      );
    });

    test('snoozes survive a save', () {
      final m = PersonalMemory()..snooze('anomaly:x', days: 3, now: now);
      final back = PersonalMemory.fromJson(m.toJson());
      expect(back.isSnoozed('anomaly:x', now), isTrue);
    });

    test('severity: risks warn, decreases are good news', () {
      expect(
        const Insight(kind: InsightKind.anomaly, priority: 1).severity,
        InsightSeverity.warning,
      );
      expect(
        const Insight(kind: InsightKind.decrease, priority: 1).severity,
        InsightSeverity.positive,
      );
      expect(
        const Insight(
          kind: InsightKind.freeMoney,
          priority: 1,
          amount: -100,
        ).severity,
        InsightSeverity.warning,
      );
    });
  });

  group('forecast and cash flow', () {
    test('the forecast carries a confidence; none without data', () {
      final s = FinoraAiSnapshot.compute(data(base()), now: now);
      expect(s.forecast.confidence, inExclusiveRange(.5, .96));
      final empty = FinoraAiSnapshot.compute(data(const []), now: now);
      expect(empty.forecast.insufficient, isNotNull);
      expect(empty.forecast.confidence, 0);
    });

    test('the timeline holds the rent and a balance for every day left', () {
      final s = FinoraAiSnapshot.compute(data(base()), now: now);
      final t = s.timeline;
      final rent = t.events.firstWhere((e) => e.title == 'Аренда');
      expect(rent.date, DateTime(2026, 11, 25));
      expect(rent.type, CashflowEventType.mandatory);
      expect(rent.detected, isFalse);
      // 20 Nov … 30 Nov.
      expect(t.balances, hasLength(11));
      expect(t.balances.first.$1, DateTime(2026, 11, 20));
      final (_, lowest) = t.lowest!;
      expect(lowest, lessThan(s.ctx.balance));
    });

    test('found regular payments join the timeline with their confidence', () {
      final entries = [
        ...base(),
        for (final m in [8, 9, 10, 11])
          e(DateTime(2026, m, 27), 399, other, payee: 'Яндекс Плюс'),
      ];
      // The November payment is not made yet: drop it.
      entries.removeWhere(
        (x) => x.payee == 'Яндекс Плюс' && x.date.month == 11,
      );
      final s = FinoraAiSnapshot.compute(data(entries), now: now);
      final plus = s.timeline.events.firstWhere(
        (e) => e.title == 'Яндекс Плюс',
      );
      expect(plus.detected, isTrue);
      expect(plus.date, DateTime(2026, 11, 27));
      expect(plus.confidence, inExclusiveRange(.5, 1));
      // The salary is a regular income and comes on the 10th, outside the
      // rest of November.
      expect(s.regularIncome.single.nextExpected, DateTime(2026, 12, 10));
    });
  });

  group('what Finora AI can do', () {
    test('«что ты умеешь?» and friends ask for the capabilities', () {
      for (final q in [
        'Что ты умеешь?',
        'что можешь',
        'Твои возможности',
        'Чем можешь помочь?',
        'Что у тебя можно спросить?',
        'помощь',
      ]) {
        expect(IntentParser.parse(q).intent, AiIntent.capabilities, reason: q);
      }
      // A money question is not mistaken for it.
      expect(
        IntentParser.parse('Сколько я могу потратить?').intent,
        AiIntent.freeMoney,
      );
    });

    test('every example in the list is really understood', () {
      for (final c in AiCapabilities.all) {
        for (final q in c.examples) {
          expect(
            IntentParser.parse(q).intent,
            isNot(AiIntent.unknown),
            reason: q,
          );
        }
      }
    });

    test('the chat lists every area', () {
      final s = FinoraAiSnapshot.compute(data(base()), now: now);
      final text = FinoraAi().answer('Что ты умеешь?', s).text;
      for (final c in AiCapabilities.all) {
        expect(text, contains(c.title));
      }
    });

    test('comparisons name their period', () {
      expect(
        IntentParser.parse('Сравни эту неделю с прошлой').period,
        PeriodUnit.week,
      );
      expect(
        IntentParser.parse('Сравни этот год с прошлым').period,
        PeriodUnit.year,
      );
      expect(
        IntentParser.parse('Сравни этот квартал с прошлым').period,
        PeriodUnit.quarter,
      );
      expect(IntentParser.parse('Сравни этот месяц с прошлым').period, isNull);
      final s = FinoraAiSnapshot.compute(data(base()), now: now);
      final week = FinoraAi().answer('Сравни эту неделю с прошлой', s).text;
      expect(week, startsWith('На этой неделе расходы'));
      final month = FinoraAi().answer('Сравни этот месяц с прошлым', s).text;
      expect(month, contains('Доходы'));
    });
  });
}
