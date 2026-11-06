import 'package:finora/domain/account_import_parser.dart';
import 'package:finora/domain/scan_document.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('nothing that is not a balance', () {
    expect(
      AccountImportParser.parse('Счета\nДобавить счёт\n12.11.2026'),
      isEmpty,
    );
    expect(AccountImportParser.parse('Карта •• 4821'), isEmpty);
  });
}
