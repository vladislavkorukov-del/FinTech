import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/conversation/conversation_context.dart';
import 'package:finora/features/finora_ai/conversation/voice_questions.dart';
import 'package:finora/features/finora_ai/models/ai_models.dart';
import 'package:finora/features/finora_ai/responses/intent_parser.dart';
import 'package:finora/features/finora_ai/services/ai_provider.dart';
import 'package:finora/features/finora_ai/services/finora_ai.dart';
import 'package:finora/presentation/finora_reactions.dart';
import 'package:finora/presentation/widgets/finora_orb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Finora AI, phase 6: the conversation's context, voice questions to the
/// engines, Finora's reaction to a closed debt, no outside AI.
void main() {
  final now = DateTime(2026, 11, 19, 12);
  final data = FinanceData(
    accounts: const [Account(id: 'card', name: 'Карта')],
    categories: const [
      Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
      Category(id: 'taxi', name: 'Такси', kind: EntryKind.expense),
      Category(id: 'loans', name: 'Кредиты', kind: EntryKind.expense),
    ],
    entries: [
      for (final (id, cat, amount, day, month) in [
        ('f1', 'food', 120000, 3, 11),
        ('f2', 'food', 80000, 10, 11),
        ('t1', 'taxi', 45000, 12, 11),
        ('f3', 'food', 150000, 5, 10),
        ('t2', 'taxi', 30000, 7, 10),
      ])
        FinanceEntry(
          id: id,
          kind: EntryKind.expense,
          amountMinor: amount,
          currency: 'RUB',
          accountId: 'card',
          categoryId: cat,
          date: DateTime(2026, month, day),
        ),
    ],
  );

  setUpAll(() => initializeDateFormatting('ru'));

  test('«сколько я потратил на …» and short follow-ups', () {
    final ctx = ConversationContext();
    ParsedQuery ask(String t) =>
        ctx.resolve(t, IntentParser.parse(t), data, now: now);
    final first = ask('Сколько я потратил на продукты?');
    expect(first.intent, AiIntent.categorySpend);
    expect(first.subject, 'food');
    final taxi = ask('а на такси?');
    expect(taxi.intent, AiIntent.categorySpend);
    expect(taxi.subject, 'taxi');
    final before = ask('а в прошлом месяце?');
    expect(before.intent, AiIntent.categorySpend);
    expect(before.subject, 'taxi');
    expect(before.previous, isTrue);
    // A comparison, then «а за неделю?» compares weeks.
    ask('сравни с прошлым месяцем');
    final week = ask('а за неделю?');
    expect(week.intent, AiIntent.compare);
    expect(week.period, PeriodUnit.week);
    expect(ask('а почему?').intent, AiIntent.whySpendingMore);
    expect(ask('подробнее').detailed, isTrue);
    // Without a previous question a follow-up stays unknown.
    expect(
      ConversationContext()
          .resolve('а за неделю?', const ParsedQuery(AiIntent.unknown), data)
          .intent,
      AiIntent.unknown,
    );
  });

  test('the answer is counted from the operations', () {
    final ai = FinoraAi();
    final s = ai.snapshot(data, now: now);
    final food = ai.answer('Сколько я потратил на продукты?', s).text;
    expect(food, contains('Продукты'));
    expect(food, contains(RegExp(r'2\s000')));
    expect(food, contains('2 операции'));
    final taxiBefore = ai.answer('а на такси в прошлом месяце?', s).text;
    expect(taxiBefore, contains('Такси'));
    expect(taxiBefore, contains('300'));
    expect(taxiBefore, contains('в прошлом месяце'));
  });

  test('voice questions go to the engines; commands do not', () {
    final reply = VoiceQuestions.answer(
      'сколько я потратил на такси',
      data,
      now: now,
    );
    expect(reply, isNotNull);
    expect(reply, contains('Такси'));
    expect(VoiceQuestions.answer('бла бла', data, now: now), isNull);
    final long = 'строка\n' * 80;
    expect(VoiceQuestions.shorten(long).length, lessThan(300));
  });

  test('Finora celebrates the payment that closes a debt', () {
    final rule = RecurringRule(
      id: 'r',
      name: 'Рассрочка',
      accountId: 'card',
      categoryId: 'loans',
      amountMinor: 100000,
      totalMinor: 200000,
      nextDate: DateTime(2026, 12, 1),
    );
    FinanceEntry pay(String id, int day) => FinanceEntry(
      id: id,
      kind: EntryKind.expense,
      amountMinor: 100000,
      currency: 'RUB',
      accountId: 'card',
      categoryId: 'loans',
      recurringRuleId: 'r',
      date: DateTime(2026, 11, day),
    );
    final half = data.copyWith(recurring: [rule], entries: [pay('p1', 1)]);
    final (mood1, _) = FinoraReactions.forEntry(
      half,
      pay('p1', 1),
      DateTime(2026, 11),
      DateTime(2026, 12),
    );
    expect(mood1, isNot(FinoraMood.delight));
    final done = half.copyWith(entries: [pay('p1', 1), pay('p2', 15)]);
    final (mood2, text) = FinoraReactions.forEntry(
      done,
      pay('p2', 15),
      DateTime(2026, 11),
      DateTime(2026, 12),
    );
    expect(mood2, FinoraMood.delight);
    expect(text, contains('закрыт'));
  });

  test('no outside AI is built in', () async {
    expect(aiProvider.available, isFalse);
    expect(await aiProvider.phrase('?', const {}), isNull);
  });
}
