import 'package:finora/domain/account_import_parser.dart';
import 'package:finora/domain/scan_document.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/zen_accounts.dart';

/// Finance 1.21: accounts with balances read from a screenshot of another
/// finance app.
void main() {
  test('names, balances, debts, currencies and card digits', () {
    const text = r'''Счета
Всего 1 284 300,50 ₽
Наличные 12 500 ₽
Тинькофф Black •• 4821   45 300,50 ₽
Сбербанк
1.200.000 ₽
Кредитка Альфа  −30 000 ₽
Доллары  $1,250.00
Копилка   7 000
Итого 1 284 300,50 ₽''';
    final drafts = AccountImportParser.parse(text);
    expect(drafts.map((d) => d.name), [
      'Наличные',
      'Тинькофф Black',
      'Сбербанк',
      'Кредитка Альфа',
      'Доллары',
      'Копилка',
    ]);
    expect(drafts.map((d) => d.amountMinor), [
      1250000,
      4530050,
      120000000,
      -3000000,
      125000,
      700000,
    ]);
    expect(drafts.map((d) => d.currency), [
      'RUB',
      'RUB',
      'RUB',
      'RUB',
      'USD',
      'RUB',
    ]);
    expect(drafts[1].lastFour, '4821');
    expect(drafts[1].bank, 'Т-Банк');
    expect(drafts[2].bank, 'Сбербанк');
    expect(drafts[0].bank, '');
  });

  test('screen geometry joins a name and its balance on one row', () {
    RecognizedLine line(String t, double left, double top) => RecognizedLine(
      text: t,
      left: left,
      top: top,
      right: left + .3,
      bottom: top + .03,
      confidence: .95,
    );
    final drafts = AccountImportParser.parse(
      '',
      lines: [
        line('Основная карта', .05, .20),
        line('84 512 ₽', .70, .205),
        line('Вклад', .05, .30),
        line('300 000,00 ₽', .65, .302),
        line('Баланс', .05, .10),
        line('384 512 ₽', .70, .10),
      ],
    );
    expect(drafts.map((d) => (d.name, d.amountMinor)), [
      ('Основная карта', 8451200),
      ('Вклад', 30000000),
    ]);
  });

  test('a real Дзен-мани list: bold names, not the thin «Личное»', () {
    // 1.22.1: the owner's screenshot came out as one account
    // «00000000 Семья Тинькофф Со…».
    const expected = [
      ('Наличные', 1000000),
      ('Бюджет', 536651),
      ('Накопления Вика', 4003249),
      ('Машина', 0),
      ('Квартира и кредиты', 0),
      ('Семья Тинькофф', 0),
      ('Совкомбанк Халва', 0),
      ('Вклад', 5668039),
    ];
    for (final psm in [3, 11]) {
      final drafts = AccountImportParser.parse('', lines: zenLines(psm));
      expect(
        drafts.map((d) => (d.name, d.amountMinor)).toList(),
        expected,
        reason: 'psm $psm',
      );
      expect(drafts.every((d) => d.currency == 'RUB'), isTrue);
      expect(
        drafts.firstWhere((d) => d.name == 'Совкомбанк Халва').bank,
        'Совкомбанк',
      );
      expect(
        drafts.firstWhere((d) => d.name == 'Семья Тинькофф').bank,
        'Т-Банк',
      );
    }
    // The same list as plain text, «Личное» under each name.
    const text = '''Наличные
Личное
10 000,00 P
Бюджет
Личное
5 366,51 Р
@ Вклад 56 680,39 Р
Личное''';
    expect(
      AccountImportParser.parse(text).map((d) => (d.name, d.amountMinor)),
      [('Наличные', 1000000), ('Бюджет', 536651), ('Вклад', 5668039)],
    );
  });

  test('nothing that is not a balance', () {
    expect(
      AccountImportParser.parse('Счета\nДобавить счёт\n12.11.2026'),
      isEmpty,
    );
    expect(AccountImportParser.parse('Карта •• 4821'), isEmpty);
  });
}
