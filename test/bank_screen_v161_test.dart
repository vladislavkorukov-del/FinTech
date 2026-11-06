import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/bank_statement_parser.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/receipt_parser.dart';
import 'package:finora/domain/scan_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finance 1.6.1 field report: a dark bank history screenshot where
/// «-10 000 ₽» became «-10 ₽» and «ОООР» was glued to the payee.
void main() {
  final now = DateTime(2026, 11, 6, 9);
  const categories = [
    Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
    Category(id: 'fun', name: 'Развлечения', kind: EntryKind.expense),
    Category(id: 'gift', name: 'Подарки', kind: EntryKind.income),
  ];
  ScanDocument parse(String text) => BankStatementParser.parse(
    text,
    categories: categories,
    now: now,
    defaultCurrency: 'RUB',
  );

  test('zero groups read as letters O are zeros, not a payee suffix', () {
    for (final (row, minor) in [
      ('Виктория Борисовна К. -10 ОООР', 1000000),
      ('Виктория Борисовна К. -10 OOO P', 1000000),
      ('Михаил Валерьевич К. +10 OOOP', 1000000),
      ('Михаил Валерьевич К. +10 0ОО ₽', 1000000),
      ('Виктория Борисовна К. +3 6ОО ₽', 360000),
      ('AVITO -2 6ОО ₽', 260000),
    ]) {
      final d = parse('Вчера\n$row\nПеревод\nКрасное и Белое -549,45 ₽');
      expect(d.isStatement, isTrue, reason: row);
      expect(d.drafts.first.amountMinor, minor, reason: row);
      expect(d.drafts.first.payee, isNot(matches(RegExp('[OО]{3}'))));
    }
  });

  test('ruble glyph read as a trailing 2 is not part of the amount', () {
    for (final (row, minor) in [
      ('Виктория Борисовна К. -10 0002', 1000000),
      ('Виктория Борисовна К. +3 6002', 360000),
      ('Whoosh - 82,902', 8290),
      ('Whoosh -26,972Р', 2697),
    ]) {
      final d = parse('Вчера\n$row\nКрасное и Белое -549,45 ₽');
      expect(d.drafts.first.amountMinor, minor, reason: row);
      expect(
        d.drafts.first.warnings.join(' '),
        contains('лишний символ'),
        reason: row,
      );
    }
  });

  test('ordinary text with ООО and real amounts is unchanged', () {
    expect(
      ReceiptParser.normalizeText('ООО Ромашка -500 ₽'),
      'ООО Ромашка -500 ₽',
    );
    expect(ReceiptParser.normalizeText('-500 ООО Ромашка'), '-500 ООО Ромашка');
    expect(ReceiptParser.normalizeText('ИНН 123 ООО'), 'ИНН 123 ООО');
    expect(ReceiptParser.normalizeText('+10 000 ₽'), '+10 000 ₽');
    expect(ReceiptParser.normalizeText('-549,45 ₽'), '-549,45 ₽');
    expect(ReceiptParser.normalizeText('-1 200 ₽'), '-1 200 ₽');
  });

  test('the reported screenshot as read by the phone gives all amounts', () {
    // Rows as recognized: amounts damaged by the thin font.
    final d = parse('''Вчера
Виктория Борисовна К. -10 ОООР
Перевод
Михаил Валерьевич К. +10 OOOP
Пополнения
AVITO -2 597 ₽
Маркетплейсы
Виктория Борисовна К. +3 6002
Пополнения
Красное и Белое -549,45Р
Супермаркеты • Карта **0091
Whoosh - 82,902
Развлечения
Whoosh -26,972Р
Развлечения
Красное и Белое -249,68P
Супермаркеты • Карта **0091''');
    expect(d.isStatement, isTrue);
    expect(d.drafts.map((e) => e.amountMinor), [
      1000000,
      1000000,
      259700,
      360000,
      54945,
      8290,
      2697,
      24968,
    ]);
    expect(d.drafts.map((e) => e.payee), [
      'Виктория Борисовна К.',
      'Михаил Валерьевич К.',
      'AVITO',
      'Виктория Борисовна К.',
      'Красное и Белое',
      'Whoosh',
      'Whoosh',
      'Красное и Белое',
    ]);
    expect(d.drafts[1].kind, EntryKind.income);
    expect(d.drafts[5].categoryId, 'fun');
  });

  RecognizedLine box(String text, double l, double t, double r, double b) =>
      RecognizedLine(
        text: text,
        left: l,
        top: t,
        right: r,
        bottom: b,
        confidence: .9,
      );

  test('amount re-reads replace the weak amount column of their row', () {
    // First pass: «-10 000 ₽» lost, icon fragments on the left, a tall icon
    // fragment spanning three rows, junk in the amount column.
    final lines = [
      box('Вчера', .05, .03, .16, .06),
      box('9', .06, .10, .14, .15),
      box('Анна Сергеевна П.', .19, .096, .65, .12),
      box('“10200 P', .76, .094, .96, .123),
      box('Перевод', .19, .138, .32, .155),
      box('AVITO', .19, .319, .31, .338),
      box('Ш А', .79, .319, .96, .338),
      box('Маркетплейсы', .19, .36, .41, .378),
      box('® =', .04, .336, .16, .499),
      box('Ольга Викторовна Д.', .19, .431, .65, .454),
      box('+3 600P', .78, .431, .96, .449),
      box('Пополнения', .19, .472, .37, .486),
    ];
    final amounts = [
      box('-10 000Р', .67, .086, 1, .129),
      box('-2 597Р', .45, .312, 1, .345),
      box('+3 600P', .67, .422, 1, .463),
    ];
    final d = BankStatementParser.parse(
      lines.map((l) => l.text).join('\n'),
      lines: lines,
      amountLines: amounts,
      categories: categories,
      now: now,
      defaultCurrency: 'RUB',
    );
    expect(d.drafts.map((e) => (e.payee, e.amountMinor, e.kind)), [
      ('Анна Сергеевна П.', 1000000, EntryKind.expense),
      ('AVITO', 259700, EntryKind.expense),
      ('Ольга Викторовна Д.', 360000, EntryKind.income),
    ]);
    // Without re-reads the damaged first reading is flagged, not trusted.
    final weak = BankStatementParser.parse(
      lines.map((l) => l.text).join('\n'),
      lines: lines,
      categories: categories,
      now: now,
      defaultCurrency: 'RUB',
    );
    expect(weak.drafts.first.amountMinor, isNot(1000000));
    expect(weak.drafts.first.kind, isNull);
  });

  test('synthetic thin-font bank screen: real OCR output, all amounts', () {
    final f =
        jsonDecode(
              File('test/fixtures/ocr/v162-bank-thin.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    List<RecognizedLine> read(String key) => [
      for (final l in (f[key] as List).cast<Map<String, dynamic>>())
        box(
          l['text'] as String,
          (l['left'] as num).toDouble(),
          (l['top'] as num).toDouble(),
          (l['right'] as num).toDouble(),
          (l['bottom'] as num).toDouble(),
        ),
    ];
    final d = BankStatementParser.parse(
      f['text'] as String,
      lines: read('lines'),
      amountLines: read('amounts'),
      categories: categories,
      now: now,
      defaultCurrency: 'RUB',
    );
    expect(d.drafts.map((e) => e.amountMinor), [
      1000000,
      1000000,
      259700,
      360000,
      54945,
      8290,
      2697,
      24968,
    ]);
    expect(d.drafts.map((e) => e.kind), [
      EntryKind.expense,
      EntryKind.income,
      EntryKind.expense,
      EntryKind.income,
      EntryKind.expense,
      EntryKind.expense,
      EntryKind.expense,
      EntryKind.expense,
    ]);
    expect(d.drafts.first.payee, 'Анна Сергеевна П.');
  });
}
