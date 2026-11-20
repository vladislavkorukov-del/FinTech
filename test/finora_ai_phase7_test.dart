import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/insights/what_if.dart';
import 'package:finora/features/finora_ai/reports/report_builder.dart';
import 'package:finora/features/finora_ai/search/smart_search.dart';
import 'package:finora/features/finora_ai/services/finora_ai.dart';
import 'package:finora/features/finora_ai/tags/tag_suggester.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Finora AI, phase 7: search in words, AI tags, reports, «что если».
void main() {
  final now = DateTime(2026, 11, 19, 12);
  FinanceEntry e(
    String id,
    String cat,
    int amount,
    DateTime date, {
    String payee = '',
    EntryKind kind = EntryKind.expense,
  }) => FinanceEntry(
    id: id,
    kind: kind,
    amountMinor: amount,
    currency: 'RUB',
    accountId: 'card',
    categoryId: cat,
    payee: payee,
    date: date,
  );
  final data = FinanceData(
    accounts: const [Account(id: 'card', name: 'Карта')],
    categories: const [
      Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
      Category(id: 'cafe', name: 'Кафе', kind: EntryKind.expense),
      Category(id: 'loans', name: 'Кредиты', kind: EntryKind.expense),
      Category(id: 'pay', name: 'Зарплата', kind: EntryKind.income),
    ],
    goals: const [
      Goal(id: 'g', name: 'Отпуск', targetMinor: 6000000, savedMinor: 0),
    ],
    recurring: [
      RecurringRule(
        id: 'loan',
        name: 'Кредитка',
        accountId: 'card',
        categoryId: 'loans',
        amountMinor: 300000,
        interestRate: 30,
        principalMinor: 6000000,
        principalDate: DateTime(2026, 11, 1),
        nextDate: DateTime(2026, 12, 5),
      ),
    ],
    entries: [
      e('p1', 'food', 45000, DateTime(2026, 10, 3), payee: 'Пятёрочка'),
      e('p2', 'food', 180000, DateTime(2026, 10, 12), payee: 'Пятёрочка'),
      e('p3', 'food', 90000, DateTime(2026, 11, 2), payee: 'Пятёрочка'),
      e('m1', 'food', 250000, DateTime(2026, 10, 20), payee: 'Магнит'),
      e('c1', 'cafe', 120000, DateTime(2026, 9, 5), payee: 'Кофемания'),
      e('c2', 'cafe', 150000, DateTime(2026, 10, 9), payee: 'Кофемания'),
      e('c3', 'cafe', 90000, DateTime(2026, 8, 14), payee: 'Кофемания'),
      e('c4', 'cafe', 60000, DateTime(2026, 11, 14), payee: 'Шоколадница'),
      for (var m = 8; m <= 11; m++)
        e(
          's$m',
          'pay',
          10000000,
          DateTime(2026, m, 10),
          payee: 'ООО Работа',
          kind: EntryKind.income,
        ),
    ],
  );
  setUpAll(() => initializeDateFormatting('ru'));

  test('a search in words', () {
    final q = SmartSearch.parse(
      'Найди траты в Пятёрочке больше 1000 за октябрь',
      data,
      now: now,
    )!;
    expect(q.kind, EntryKind.expense);
    expect(q.minMinor, 100000);
    expect(q.start, DateTime(2026, 10));
    expect(q.end, DateTime(2026, 11));
    expect(q.text, contains('пятероч'));
    final r = SmartSearch.run(q, data);
    expect(r.entries.map((x) => x.id), ['p2']);
    expect(r.totalMinor, 180000);
    expect(SmartSearch.answer(r, data), contains('Нашла 1'));
    // The biggest ones.
    final big = SmartSearch.parse(
      'самые крупные расходы в прошлом месяце',
      data,
      now: now,
    )!;
    final top = SmartSearch.run(big, data).entries;
    expect(top.first.id, 'm1');
    // A plain list request stays the voice command's.
    expect(SmartSearch.parse('покажи расходы за июнь', data, now: now), isNull);
    expect(SmartSearch.parse('как дела', data, now: now), isNull);
    // Category search.
    final cafe = SmartSearch.parse('покажи кафе дешевле 1000', data, now: now)!;
    expect(cafe.categoryId, 'cafe');
    expect(SmartSearch.run(cafe, data).entries.map((x) => x.id), ['c4', 'c3']);
  });

  test('AI tags are suggestions, never the category', () {
    final tags = TagSuggester.suggest(
      data,
      kind: EntryKind.expense,
      amountMinor: 900000,
      payee: 'Кофемания',
      date: DateTime(2026, 11, 21), // Saturday
      categoryId: 'cafe',
    );
    expect(tags, containsAll(['выходные', 'регулярно']));
    expect(
      TagSuggester.suggest(
        data,
        kind: EntryKind.expense,
        amountMinor: 1000,
        payee: 'Кофемания',
        date: DateTime(2026, 11, 21),
        categoryId: 'cafe',
        existing: ['выходные'],
      ),
      isNot(contains('выходные')),
    );
    expect(
      TagSuggester.suggest(
        data,
        kind: EntryKind.income,
        amountMinor: 45000,
        payee: 'Пятёрочка',
        date: DateTime(2026, 11, 18),
      ),
      contains('возврат'),
    );
  });

  test('a report counts the period and compares it', () {
    final r = ReportBuilder.build(
      data,
      period: ReportPeriod.month,
      previous: true,
      now: now,
    );
    expect(r.start, DateTime(2026, 10));
    expect(r.incomeMinor, 10000000);
    expect(r.expenseMinor, 45000 + 180000 + 250000 + 150000);
    expect(r.categories.first.id, 'food');
    expect(r.biggest!.id, 'm1');
    expect(r.savedPercent, greaterThan(90));
    final text = ReportBuilder.text(r);
    expect(text, contains('Отчёт за октябрь 2026'));
    expect(text, contains('Магнит'));
    expect(ReportBuilder.parseRequest('отчёт за прошлую неделю'), (
      ReportPeriod.week,
      true,
    ));
    expect(ReportBuilder.parseRequest('дайджест'), (ReportPeriod.month, false));
    expect(ReportBuilder.parseRequest('как дела'), isNull);
  });

  test('what if: cut, save, pay early, earn more', () {
    final cut = WhatIf.answer(
      data,
      'что если сократить кафе на 20%',
      now: now,
    )!;
    // Aug–Oct: 900 + 1200 + 1500 = 3600 ₽ → 1200 ₽ a month, 20 % = 240 ₽.
    expect(cut, contains(RegExp(r'1\s200')));
    expect(cut, contains('240'));
    expect(cut, contains(RegExp(r'2\s880')));
    final save = WhatIf.answer(
      data,
      'что если откладывать 5000 в месяц',
      now: now,
    )!;
    expect(save, contains(RegExp(r'60\s000')));
    expect(save, contains('Отпуск'));
    expect(save, contains('12 мес'));
    final early = WhatIf.answer(
      data,
      'что если досрочно внести 20 000 в кредит',
      now: now,
    )!;
    expect(early, contains('Кредитка'));
    expect(early, contains('переплата меньше'));
    final income = WhatIf.answer(
      data,
      'что если доход вырастет на 10 000',
      now: now,
    )!;
    expect(income, contains('вырастет'));
    expect(WhatIf.answer(data, 'сколько я потратил', now: now), isNull);
  });

  test('the engines answer these questions too (chat and voice)', () {
    final ai = FinoraAi();
    final s = ai.snapshot(data, now: now);
    expect(ai.answer('отчёт за прошлый месяц', s).text, contains('Отчёт за'));
    expect(
      ai.answer('найди траты в Пятёрочке больше 1000 за октябрь', s).text,
      contains('Нашла 1'),
    );
    expect(
      ai.answer('что если откладывать 5000 в месяц', s).text,
      contains('за год'),
    );
  });
}
