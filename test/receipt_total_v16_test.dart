import 'package:finora/domain/bank_statement_parser.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/receipt_parser.dart';
import 'package:finora/domain/scan_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finance 1.6: a till receipt is one operation with its explicit total.
/// Item prices, VAT, tender, change and payment methods never become
/// separate operations and are never summed into an invented total.
void main() {
  final now = DateTime(2026, 11, 5, 17, 25);
  const categories = [
    Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
    Category(id: 'cafe', name: 'Кафе и рестораны', kind: EntryKind.expense),
    Category(id: 'other', name: 'Прочее', kind: EntryKind.expense),
    Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
  ];
  ScanDocument scan(String text, {List<RecognizedLine> lines = const []}) =>
      BankStatementParser.parse(
        text,
        lines: lines,
        categories: categories,
        now: now,
        defaultCurrency: 'RUB',
      );
  RecognizedLine at(String text, double left, double right, double top) =>
      RecognizedLine(
        text: text,
        left: left,
        top: top,
        right: right,
        bottom: top + .02,
        confidence: .93,
      );
  void single(ScanDocument d, int? amount, {String? reason}) {
    expect(d.isStatement, isFalse, reason: reason);
    expect(d.drafts, hasLength(1), reason: reason);
    expect(d.drafts.single.amountMinor, amount, reason: reason);
  }

  test('many item prices, VAT, tender and change give one total', () {
    const text = '''ПЯТЁРОЧКА
КАССОВЫЙ ЧЕК ПРИХОД
Молоко 3,2% 2 x 89,99 =179,98 ₽
Хлеб Бородинский 1 x 45,00 =45,00 ₽
Сыр Российский 0,352 кг x 799,00 =281,25 ₽
Пакет 1 x 9,99 =9,99 ₽
ИТОГ =516,22 ₽
НДС 20% =52,30
НДС 10% =18,40
БЕЗНАЛИЧНЫМИ =516,22
НАЛИЧНЫМИ =0,00
ВНЕСЕНО =516,22
СДАЧА =0,00
ФН 7380440700123456 ФД 12345 ФП 3456789012
05.11.2026 17:21''';
    final d = scan(text);
    single(d, 51622);
    expect(d.drafts.single.kind, EntryKind.expense);
    expect(d.drafts.single.currency, 'RUB');
  });

  test('total printed on the next line', () {
    single(
      scan(
        'Магнит\nКассовый чек\nКофе 1 x 499,00 =499,00\nПеченье 2 x 79,50 =159,00\nИТОГО\n=658,00\nБЕЗНАЛИЧНЫМИ\n=658,00',
      ),
      65800,
    );
    single(
      scan(
        'Кофейня\nЛатте 1 x 290,00\nКруассан 1 x 210,00\nИТОГ К ОПЛАТЕ\n500,00 ₽',
      ),
      50000,
    );
  });

  test('total in a separate right column is joined by row geometry', () {
    // Tesseract reading order lists the whole label column first, then the
    // value column; only coordinates connect «ИТОГ» with its value.
    const text =
        'ВкусВилл\nКассовый чек\nБанан\nЙогурт\nИТОГ\nНДС 10%\nБЕЗНАЛИЧНЫМИ\n'
        '=129,90\n=89,90\n=219,80\n=19,98\n=219,80';
    final lines = [
      at('ВкусВилл', .30, .70, .05),
      at('Кассовый чек', .30, .70, .09),
      at('Банан', .05, .40, .20),
      at('=129,90', .70, .95, .201),
      at('Йогурт', .05, .40, .24),
      at('=89,90', .70, .95, .241),
      at('ИТОГ', .05, .30, .30),
      at('=219,80', .70, .95, .302),
      at('НДС 10%', .05, .40, .34),
      at('=19,98', .70, .95, .341),
      at('БЕЗНАЛИЧНЫМИ', .05, .50, .38),
      at('=219,80', .70, .95, .381),
    ];
    final d = scan(text, lines: lines);
    single(d, 21980);
    expect(d.drafts.single.rawText, text);
    // Without coordinates the label is not tied to its value: the amount is
    // only ever taken from the «ИТОГ» row, so it stays empty for review.
    single(scan(text), null);
  });

  test('OCR spaces and mixed Latin letters inside the total label', () {
    for (final label in [
      'И Т О Г',
      'И Т О Г О',
      'ИT0Г',
      'ИТOГО',
      'итог',
      'Итого:',
      'К 0ПЛАТЕ',
      'КОПЛАТЕ',
    ]) {
      single(
        scan(
          'ЛЕНТА\nКассовый чек\nВода 1 x 59,90 =59,90 ₽\nСок 1 x 129,00 =129,00 ₽\n$label =188,90 ₽\nСДАЧА 11,10 ₽',
        ),
        18890,
        reason: label,
      );
    }
    expect(ReceiptParser.parseAmount('188 ,90'), 18890);
    expect(ReceiptParser.parseAmount('1 188 , 90'), 118890);
  });

  test('receipt whose header OCR lost is still not split into a list', () {
    // No shop name, no «кассовый чек», no fiscal block: item rows remain.
    single(
      scan(
        'Молоко 2 x 89,99 =179,98 ₽\nХлеб 1 x 45,00 =45,00 ₽\nСыр 1 x 320,00 =320,00 ₽\nИТОГ =544,98 ₽',
      ),
      54498,
    );
    // Only tender and total survived, and the list words are nearby.
    single(
      scan(
        'Операции\nКофе 250,00 ₽\nСэндвич 310,00 ₽\nИтого 560,00 ₽\nБезналичными 560,00 ₽',
      ),
      56000,
    );
  });

  test('missing or ambiguous total stays empty for review', () {
    final missing = scan(
      'Кассовый чек\nМолоко 2 x 89,99 =179,98 ₽\nХлеб 1 x 45,00 =45,00 ₽\nБЕЗНАЛИЧНЫМИ',
    );
    single(missing, null);
    expect(
      missing.drafts.single.warnings.join(' '),
      contains('Итог чека не найден'),
    );
    // Owner's rule: no «ИТОГ» row, no amount — not even the card payment.
    final partial = scan(
      'Молоко 2 x 89,99 =179,98 ₽\nХлеб 1 x 45,00 =45,00 ₽\nОПЛАТА КАРТОЙ 224,98 ₽',
    );
    single(partial, null);
    final itemsOnly = scan(
      'Кассовый чек\nМолоко 2 x 89,99 =179,98 ₽\nХлеб 1 x 45,00 =45,00 ₽\nСыр 1 x 320,00 =320,00 ₽',
    );
    single(itemsOnly, null);
    final ambiguous = scan(
      'Кассовый чек\nХлеб 1 x 45,00\nИТОГ 145,00 ₽\nИТОГ 154,00 ₽',
    );
    single(ambiguous, null);
    expect(
      ambiguous.drafts.single.warnings.join(' '),
      contains('несколько возможных итоговых сумм'),
    );
  });

  test('bank history page still becomes several operations', () {
    final d = scan(
      'История операций\nСегодня\nПятёрочка -524,90 ₽\nЯндекс Go -312 ₽\nЗарплата +85 000 ₽\nВчера\nАптека -1 250,50 ₽',
    );
    expect(d.isStatement, isTrue);
    expect(d.drafts.map((d) => d.amountMinor), [52490, 31200, 8500000, 125050]);
    expect(d.drafts[2].kind, EntryKind.income);
  });
}
