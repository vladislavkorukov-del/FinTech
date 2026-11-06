import 'package:finora/data/demo_data.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/voice_entry_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finance 1.19: a spoken phrase becomes an operation draft (reviewed in the
/// editor before saving).
void main() {
  final categories = createDemoData(DateTime(2026, 11, 6)).categories;
  final now = DateTime(2026, 11, 6, 15, 30);
  String? name(String? id) =>
      categories.where((c) => c.id == id).map((c) => c.name).firstOrNull;
  VoiceDraft parse(String text, {List<FinanceEntry> history = const []}) =>
      VoiceEntryParser.parse(
        text,
        categories: categories,
        history: history,
        now: now,
      );

  test('stores, amounts and categories from everyday phrases', () {
    final cases = <String, (EntryKind, int, String, String?)>{
      'Пятёрочка 450 рублей': (
        EntryKind.expense,
        45000,
        'Пятёрочка',
        'Продукты',
      ),
      'потратил 1 250 рублей в пятерочке': (
        EntryKind.expense,
        125000,
        'Пятёрочка',
        'Продукты',
      ),
      'в магните 780': (EntryKind.expense, 78000, 'Магнит', 'Продукты'),
      'Whoosh 189 рублей': (EntryKind.expense, 18900, 'Whoosh', 'Транспорт'),
      'вуш 150': (EntryKind.expense, 15000, 'Whoosh', 'Транспорт'),
      'вкусно и точка 420 рублей': (
        EntryKind.expense,
        42000,
        'Вкусно — и точка',
        'Кафе и рестораны',
      ),
      'заказ на озоне 2 499 рублей': (
        EntryKind.expense,
        249900,
        'Ozon',
        'Покупки',
      ),
      'кофе 250': (EntryKind.expense, 25000, 'Кофе', 'Кафе и рестораны'),
      'такси 600 рублей': (EntryKind.expense, 60000, 'Такси', 'Транспорт'),
      'бензин 3500': (EntryKind.expense, 350000, 'Бензин', 'Автомобиль'),
      'на продукты 1200': (EntryKind.expense, 120000, 'Продукты', 'Продукты'),
      'аптека 560 рублей 50 копеек': (
        EntryKind.expense,
        56050,
        'Аптека',
        'Аптека',
      ),
      'зарплата 90 тысяч': (EntryKind.income, 9000000, 'Зарплата', 'Зарплата'),
      'пришла зарплата 85 тысяч 500': (
        EntryKind.income,
        8550000,
        'Зарплата',
        'Зарплата',
      ),
      'кэшбэк 312 рублей': (EntryKind.income, 31200, 'Кэшбэк', null),
      'подработка 5000': (EntryKind.income, 500000, 'Подработка', 'Подработка'),
      'интернет полторы тысячи': (EntryKind.expense, 150000, 'Интернет', null),
    };
    for (final MapEntry(key: text, value: want) in cases.entries) {
      final d = parse(text);
      expect(d.kind, want.$1, reason: text);
      expect(d.amountMinor, want.$2, reason: text);
      expect(d.payee, want.$3, reason: text);
      if (want.$4 != null) expect(name(d.categoryId), want.$4, reason: text);
      expect(d.heard, text);
    }
  });

  test('dates, store logos and the person\'s own choice', () {
    expect(parse('такси вчера 500').date, DateTime(2026, 11, 5, 15, 30));
    expect(parse('позавчера кофе 200').date, DateTime(2026, 11, 4, 15, 30));
    expect(parse('кофе 200').date, isNull);
    expect(parse('в пятерочке 300').serviceId, 'store_pyaterochka');
    expect(parse('кофе 200').serviceId, isNull);
    final fun = categories.firstWhere((c) => c.name == 'Развлечения');
    final d = parse(
      'вуш 150',
      history: [
        FinanceEntry(
          id: 'h',
          kind: EntryKind.expense,
          amountMinor: 100,
          currency: 'RUB',
          accountId: 'card',
          categoryId: fun.id,
          date: DateTime(2026, 10, 1),
          payee: 'Whoosh',
        ),
      ],
    );
    expect(d.categoryId, fun.id);
  });

  test('no amount heard, and the best of several hypotheses', () {
    final none = parse('пятерочка');
    expect(none.amountMinor, isNull);
    expect(none.payee, 'Пятёрочка');
    final best = VoiceEntryParser.parseBest(
      ['пятерочка', 'пятерочка 450 рублей'],
      categories: categories,
      now: now,
    );
    expect(best.amountMinor, 45000);
    expect(
      VoiceEntryParser.parseBest(const [], categories: categories).heard,
      '',
    );
  });
}
