import 'package:finora/data/demo_data.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/voice_command_parser.dart';
import 'package:finora/domain/voice_entry_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finora 1.33: required payments by voice and names with digits.
void main() {
  final now = DateTime(2026, 11, 7);
  final demo = createDemoData(now);
  const accounts = [Account(id: 'sb', name: 'Сбербанк')];

  CreateRecurringCommand rule(String phrase) =>
      VoiceCommandParser.parse(
            [phrase],
            categories: demo.categories,
            accounts: accounts,
            now: now,
          )!
          as CreateRecurringCommand;
  String category(String? id) =>
      demo.categories.firstWhere((c) => c.id == id).name;

  group('required payments', () {
    for (final (phrase, name, amount, day) in [
      ('обязательный платеж кредит 15000 25 числа', 'Кредит', 1500000, 25),
      (
        'Обязательный платёж кредит 15 000 рублей 25-го числа',
        'Кредит',
        1500000,
        25,
      ),
      (
        'обязательный платеж ипотека 32 000 рублей 5 числа',
        'Ипотека',
        3200000,
        5,
      ),
      ('добавь обязательный платеж аренда 40 тысяч', 'Аренда', 4000000, null),
      ('платеж по кредиту 12 500 каждый месяц 10 числа', 'Кредит', 1250000, 10),
      ('кредит 15 тысяч каждый месяц', 'Кредит', 1500000, null),
      ('ипотека 32000 ежемесячно', 'Ипотека', 3200000, null),
      ('коммуналка 6 500 рублей 20 числа', 'Коммунальные', 650000, 20),
      (
        'обязательный платеж кредитка 3000 каждое 15 число',
        'Кредитная карта',
        300000,
        15,
      ),
      ('обязательный платеж 5000 1 числа', 'Обязательный платёж', 500000, 1),
    ]) {
      test(phrase, () {
        final r = rule(phrase);
        expect(r.name, name);
        expect(r.amountMinor, amount);
        expect(r.paymentType, 'mandatory');
        expect(r.kind, EntryKind.expense);
        if (day != null) expect(r.nextDate.day, day);
      });
    }

    test('a date said with the month', () {
      final r = rule('обязательный платеж кредит 15000 рублей 25 ноября');
      expect(r.nextDate, DateTime(2026, 11, 25));
      expect(r.amountMinor, 1500000);
      final early = rule('обязательный платеж страховка 9000 3 ноября');
      expect(early.nextDate, DateTime(2027, 11, 3));
      expect(early.name, 'Страховка');
    });

    test('a loan payment is in «Кредиты»', () {
      expect(
        category(rule('обязательный платеж кредит 15000').categoryId),
        'Кредиты',
      );
    });

    test('salary every month stays income', () {
      final r = rule('зарплата 90 тысяч каждый месяц 10 числа');
      expect(r.kind, EntryKind.income);
      expect(r.amountMinor, 9000000);
      expect(r.nextDate, DateTime(2026, 11, 10));
    });
  });

  group('names with digits', () {
    for (final (phrase, name, amount) in [
      ('подписка теле2 695 рублей', 'Т2', 69500),
      ('подписка Теле2 695 рублей в месяц', 'Т2', 69500),
      ('подписка теле 2 695 рублей', 'Т2', 69500),
      ('теле2 695 рублей каждый месяц', 'Т2', 69500),
      ('т2 695 руб в месяц', 'Т2', 69500),
      ('подписка Tele2 695', 'Т2', 69500),
      ('подписка Яндекс 360 349 рублей в месяц', 'Яндекс 360', 34900),
      ('подписка microsoft 365 299 рублей в месяц', 'Microsoft 365', 29900),
      ('подписка 1password 300 рублей в месяц', '1Password', 30000),
    ]) {
      test(phrase, () {
        final r = rule(phrase);
        expect(r.name, name);
        expect(r.amountMinor, amount);
        expect(r.serviceId, isNotNull);
      });
    }

    for (final (phrase, payee, amount) in [
      ('теле2 695 рублей', 'Т2', 69500),
      ('теле 2 695 рублей', 'Т2', 69500),
      ('Т2 695', 'Т2', 69500),
      ('Tele2 1 200 рублей', 'Т2', 120000),
      ('яндекс 360 349', 'Яндекс 360', 34900),
      ('аптека 36,6 450 рублей', 'Аптека 36,6', 45000),
    ]) {
      test('entry: $phrase', () {
        final d = VoiceEntryParser.parse(phrase, categories: demo.categories);
        expect(d.amountMinor, amount);
        expect(d.payee, payee);
      });
    }

    test('ordinary thousands still merge', () {
      expect(
        VoiceEntryParser.parse(
          'кофе 1 300',
          categories: demo.categories,
        ).amountMinor,
        130000,
      );
      expect(
        VoiceEntryParser.parse(
          'ноутбук 85 000 рублей',
          categories: demo.categories,
        ).amountMinor,
        8500000,
      );
      expect(
        VoiceEntryParser.parse(
          'часы 12 500',
          categories: demo.categories,
        ).amountMinor,
        1250000,
      );
    });
  });

  test('a one-off payment is still an operation', () {
    for (final phrase in [
      'оплатил подписку нетфликс 799',
      'кредит 15000',
      'пятерочка 450 рублей',
      'часы 5000',
    ]) {
      expect(
        VoiceCommandParser.parse(
          [phrase],
          categories: demo.categories,
          now: now,
        ),
        isNull,
        reason: phrase,
      );
    }
  });
}
