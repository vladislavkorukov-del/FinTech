import 'dart:convert';
import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/classification/transaction_classifier.dart';
import 'package:finora/features/finora_ai/inference/features.dart';
import 'package:finora/features/finora_ai/inference/linear_model.dart';
import 'package:finora/features/finora_ai/memory/personal_memory.dart';
import 'package:finora/features/finora_ai/models/ai_models.dart';
import 'package:finora/features/finora_ai/personalization/feedback.dart';
import 'package:finora/features/finora_ai/repositories/memory_repository.dart';
import 'package:finora/features/finora_ai/responses/intent_parser.dart';
import 'package:finora/features/finora_ai/responses/response_layer.dart';
import 'package:finora/features/finora_ai/services/finora_ai.dart';
import 'package:finora/features/finora_ai/services/finora_ai_snapshot.dart';
import 'package:finora/presentation/widgets/common.dart' show money;
import 'package:flutter_test/flutter_test.dart';

/// Finora AI: facts first (engines), words second (response layer).
void main() {
  final now = DateTime(2026, 11, 20, 12);
  const groceries = 'expense-0', cafe = 'expense-1', shopping = 'expense-10';
  const pharmacy = 'expense-7', subscriptions = 'expense-9';
  var n = 0;
  FinanceEntry e(
    DateTime d,
    int rub,
    String category, {
    String payee = '',
    EntryKind kind = EntryKind.expense,
  }) => FinanceEntry(
    id: 'e${n++}',
    kind: kind,
    amountMinor: rub * 100,
    currency: 'RUB',
    accountId: 'card',
    categoryId: category,
    payee: payee,
    date: d,
  );

  List<FinanceEntry> history() {
    final out = <FinanceEntry>[];
    for (final m in [8, 9, 10]) {
      for (final day in [2, 6, 10, 14, 18, 22, 26]) {
        out.add(e(DateTime(2026, m, day), 1400, groceries, payee: 'Пятёрочка'));
      }
      for (final day in [3, 9, 15, 21]) {
        out.add(e(DateTime(2026, m, day), 1000, cafe, payee: 'Шоколадница'));
      }
      for (final day in [4, 12, 19]) {
        out.add(e(DateTime(2026, m, day), 1500, shopping, payee: 'Fix Price'));
      }
      out
        ..add(e(DateTime(2026, m, 5), 169, subscriptions, payee: 'Spotify'))
        ..add(
          e(
            DateTime(2026, m, 10),
            100000,
            'income-0',
            payee: 'Зарплата',
            kind: EntryKind.income,
          ),
        );
    }
    // November so far: the café doubles, a big one-off purchase.
    for (final day in [2, 6, 10, 14, 18]) {
      out.add(e(DateTime(2026, 11, day), 1400, groceries, payee: 'Пятёрочка'));
    }
    for (final day in [1, 4, 7, 9, 12, 15, 18]) {
      out.add(e(DateTime(2026, 11, day), 1300, cafe, payee: 'Шоколадница'));
    }
    out
      ..add(e(DateTime(2026, 11, 5), 169, subscriptions, payee: 'Spotify'))
      ..add(e(DateTime(2026, 11, 16), 25000, shopping, payee: 'М.Видео'))
      ..add(
        e(
          DateTime(2026, 11, 10),
          100000,
          'income-0',
          payee: 'Зарплата',
          kind: EntryKind.income,
        ),
      );
    return out;
  }

  FinanceData data({List<FinanceEntry>? entries, List<Budget>? budgets}) {
    final demo = createDemoData(now);
    return demo.copyWith(
      entries: entries ?? history(),
      budgets: budgets ?? const [],
      goals: const [],
      recurring: [
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
      preferences: demo.preferences.copyWith(monthStart: 1),
    );
  }

  group('engines', () {
    test('month comparison finds what drives the growth', () {
      final s = FinoraAiSnapshot.compute(data(), now: now);
      final c = s.comparison;
      expect(c.insufficient, isNull);
      expect(c.drivers.first.categoryId, shopping); // the 25 000 purchase
      final cafeChange = c.drivers.firstWhere((d) => d.categoryId == cafe);
      // Nov 1–20: 7 × 1 300; Oct 1–20: days 3, 9, 15 × 1 000.
      expect(cafeChange.current, 910000);
      expect(cafeChange.previous, 300000);
    });

    test('a monthly Spotify payment is a possible subscription', () {
      final s = FinoraAiSnapshot.compute(data(), now: now);
      final spotify = s.subscriptions.where((r) => r.merchantKey == 'spotify');
      expect(spotify, hasLength(1));
      expect(spotify.single.cadence, Cadence.monthly);
      expect(spotify.single.typicalAmount, 16900);
      expect(spotify.single.occurrences, 4);
    });

    test('a rejected subscription stays quiet until there are new grounds', () {
      final memory = PersonalMemory();
      var s = FinoraAiSnapshot.compute(data(), memory: memory, now: now);
      Feedback.rejectSubscription(memory, s.subscriptions.single);
      s = FinoraAiSnapshot.compute(data(), memory: memory, now: now);
      expect(s.subscriptions, isEmpty);
      // Three more months of the same payment: suggested again.
      final more = [
        ...history(),
        for (final m in [12, 13, 14])
          e(DateTime(2026, m, 5), 169, subscriptions, payee: 'Spotify'),
      ];
      final later = DateTime(2027, 2, 20);
      s = FinoraAiSnapshot.compute(
        data(entries: more),
        memory: memory,
        now: later,
      );
      expect(s.subscriptions.map((r) => r.merchantKey), contains('spotify'));
    });

    test('a big purchase at a new place is an unplanned anomaly', () {
      final s = FinoraAiSnapshot.compute(data(), now: now);
      expect(s.anomalies, hasLength(1));
      final a = s.anomalies.single;
      expect(a.entry.amountMinor, 2500000);
      expect(a.typical, 150000);
      expect(a.firstAtMerchant, isTrue);
    });

    test('free money after mandatory payments and the forecast', () {
      final s = FinoraAiSnapshot.compute(data(), now: now);
      expect(s.cashflow.mandatory, 3000000);
      expect(
        s.cashflow.afterMandatory,
        s.cashflow.balance + s.cashflow.expectedIncome - 3000000,
      );
      final f = s.forecast;
      expect(f.insufficient, isNull);
      expect(f.projectedExpense, greaterThan(f.spentSoFar + 3000000));
      expect(f.projectedIncome, 10000000);
      expect(
        f.projectedBalance,
        f.currentBalance +
            (f.projectedIncome - f.incomeSoFar) -
            (f.projectedExpense - f.spentSoFar),
      );
    });

    test('a budget already exceeded is certain to be exceeded', () {
      final s = FinoraAiSnapshot.compute(
        data(
          budgets: const [
            Budget(id: 'b', name: 'Кафе', categoryId: cafe, limitMinor: 800000),
          ],
        ),
        now: now,
      );
      final r = s.risks.single;
      expect(r.spent, 910000);
      expect(r.probability, 1);
      expect(r.overrun, greaterThan(110000 - 1));
    });

    test('budget suggestions come from the usual monthly spending', () {
      final s = FinoraAiSnapshot.compute(data(), now: now);
      final groceriesSuggestion = s.budgetSuggestions.firstWhere(
        (b) => b.categoryId == groceries,
      );
      // 7 × 1 400 = 9 800 a month → rounded up to 10 000.
      expect(groceriesSuggestion.limit, 1000000);
    });

    test('with no operations Finora says she has too little data', () {
      final s = FinoraAiSnapshot.compute(data(entries: const []), now: now);
      expect(s.forecast.insufficient, isNotNull);
      expect(s.comparison.insufficient, isNotNull);
      expect(ResponseLayer.forecast(s), ResponseLayer.needHistory);
      expect(ResponseLayer.whySpendingMore(s), ResponseLayer.notEnough);
      expect(s.insights.single.kind, InsightKind.notEnoughData);
    });
  });

  group('response layer only words the engines\' numbers', () {
    test('why spending more quotes the comparison', () {
      final s = FinoraAiSnapshot.compute(data(), now: now);
      final text = ResponseLayer.whySpendingMore(s);
      expect(
        text,
        contains(money(s.comparison.drivers.first.difference, 'RUB')),
      );
      expect(text, contains('покупки'));
    });

    test('every insight sentence carries its own amount', () {
      final s = FinoraAiSnapshot.compute(data(), now: now);
      for (final i in s.insights) {
        final text = ResponseLayer.insight(s, i);
        expect(text, isNotEmpty);
        if (i.amount != null && i.kind != InsightKind.subscription) {
          expect(text, contains(money(i.amount!.abs(), 'RUB')), reason: '$i');
        }
      }
    });

    test('the subscription sentence names the payment', () {
      final s = FinoraAiSnapshot.compute(data(), now: now);
      final i = s.insights.firstWhere(
        (i) => i.kind == InsightKind.subscription,
      );
      expect(
        ResponseLayer.insight(s, i),
        'Я заметила платёж ${money(16900, 'RUB')} «Spotify» примерно раз в '
        'месяц. Возможно, это подписка.',
      );
    });
  });

  group('classification', () {
    test('the person\'s choice beats the catalog', () {
      final memory = PersonalMemory();
      for (var i = 0; i < 3; i++) {
        memory.observe('вкусвилл', cafe);
      }
      final r = const TransactionClassifier().classify(
        merchant: 'ВкусВилл',
        amountMinor: 50000,
        kind: EntryKind.expense,
        data: data(entries: const []),
        memory: memory,
      );
      expect(r.best!.categoryId, cafe);
      expect(r.best!.source, ClassificationSource.memory);
    });

    test('a correction outweighs earlier saves', () {
      final memory = PersonalMemory();
      final d = data(entries: const []);
      final before = e(DateTime(2026, 11, 1), 500, cafe, payee: 'Самокат');
      Feedback.observeSave(memory, before);
      Feedback.observeSave(
        memory,
        e(DateTime(2026, 11, 1), 500, groceries, payee: 'Самокат'),
        before: before,
      );
      expect(memory.corrections.single.to, groceries);
      final r = const TransactionClassifier().classify(
        merchant: 'Самокат',
        amountMinor: 50000,
        kind: EntryKind.expense,
        data: d,
        memory: memory,
      );
      expect(r.best!.categoryId, groceries);
    });

    test('an unknown word without a model is «not sure»', () {
      final r = const TransactionClassifier().classify(
        merchant: 'Зюзюкин',
        amountMinor: 50000,
        kind: EntryKind.expense,
        data: data(entries: const []),
      );
      expect(r.best, isNull);
      expect(r.insufficient!.reason, InsufficientReason.lowConfidence);
    });

    test('the local model files a pharmacy and reports its version', () {
      final model = LinearModel.parse(
        File('assets/ai/finora_classifier.json').readAsStringSync(),
      );
      final r = TransactionClassifier(model: model).classify(
        merchant: 'Аптека у дома 24',
        amountMinor: 64000,
        kind: EntryKind.expense,
        data: data(entries: const []),
      );
      expect(r.best!.categoryId, pharmacy);
      expect(r.modelVersion, model.version);
    });
  });

  group('local model', () {
    final model = LinearModel.parse(
      File('assets/ai/finora_classifier.json').readAsStringSync(),
    );

    test('Dart inference matches the Python trainer on shared fixtures', () {
      final fixtures =
          jsonDecode(
                File('test/fixtures/finora_ai_parity.json').readAsStringSync(),
              )
              as List;
      for (final f in fixtures.cast<Map<String, dynamic>>()) {
        final top = model
            .predict(
              TransactionInput(
                merchant: f['merchant'] as String,
                amountMinor: f['amount_minor'] as int,
                kind: f['kind'] as String,
                accountType: f['account_type'] as String,
                date: DateTime.parse(f['date'] as String),
              ),
            )
            .first;
        expect(top.$1, f['class'], reason: f['merchant'] as String);
        expect(top.$2, closeTo((f['p'] as num).toDouble(), 2e-3));
      }
    });

    test('features: normalisation, hashing and amount buckets', () {
      expect(
        Features.normalize('  MAGNIT  MM-Кострома №5 '),
        'magnit mm кострома 5',
      );
      expect(Features.normalize('Ёлка'), 'елка');
      expect(Features.fnv1a('a'), 0xe40c292c);
      expect(Features.amountBucket(99), 0);
      expect(Features.amountBucket(100), 0);
      expect(Features.amountBucket(80000), 9);
    });
  });

  group('memory', () {
    test('survives a save and reload', () async {
      final dir = await Directory.systemTemp.createTemp('finora-ai-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/m.json');
      final repo = MemoryRepository(file: file);
      final m = await repo.load();
      m.observe('пятерочка', groceries);
      m.reject('subscription:spotify', evidence: 4);
      await repo.save();
      final again = await MemoryRepository(file: file).load();
      expect(again.categoryFor('пятерочка')!.categoryId, groceries);
      expect(again.stillRejected('subscription:spotify', 5), isTrue);
      expect(again.stillRejected('subscription:spotify', 7), isFalse);
    });
  });

  group('questions', () {
    test('intent parser', () {
      expect(
        IntentParser.parse('Почему я в этом месяце трачу больше?').intent,
        AiIntent.whySpendingMore,
      );
      expect(IntentParser.parse('Какой прогноз?').intent, AiIntent.forecast);
      expect(
        IntentParser.parse('Сколько останется после обязательных?').intent,
        AiIntent.freeMoney,
      );
      expect(
        IntentParser.parse('Есть подписки?').intent,
        AiIntent.subscriptions,
      );
      expect(
        IntentParser.parse('Предложи бюджет').intent,
        AiIntent.budgetAdvice,
      );
      final q = IntentParser.parse('К какой категории Аптека Ригла?');
      expect(q.intent, AiIntent.categorize);
      expect(q.subject, 'Аптека Ригла');
      expect(IntentParser.parse('расскажи анекдот').intent, AiIntent.unknown);
    });

    test('answers come from the snapshot', () {
      final ai = FinoraAi(memory: MemoryRepository());
      final s = ai.snapshot(data(), now: now);
      final a = ai.answer('Сколько останется после обязательных платежей?', s);
      expect(a.text, contains(money(s.cashflow.afterMandatory, 'RUB')));
      final b = ai.answer('Есть ли у меня подписки?', s);
      expect(b.text, contains('Spotify'));
    });
  });
}
