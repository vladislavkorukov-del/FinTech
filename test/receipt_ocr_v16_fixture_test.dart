import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/bank_statement_parser.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/receipt_total.dart';
import 'package:finora/domain/scan_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// Actual host Tesseract 5 output (bundled rus+eng models) for synthetic
/// till-receipt photos: shadows, rotation, blur, noise, JPEG. See
/// test/fixtures/ocr/README.md. OCR mistakes are kept exactly as read.
void main() {
  final fixtures =
      (jsonDecode(
                File('test/fixtures/ocr/v16-receipts.json').readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();

  test('fixtures are present', () => expect(fixtures, hasLength(19)));
  for (final f in fixtures) {
    test('${f['name']}: ${f['note']}', () {
      final lines = [
        for (final l in (f['lines'] as List).cast<Map<String, dynamic>>())
          RecognizedLine(
            text: l['text'] as String,
            left: (l['left'] as num).toDouble(),
            top: (l['top'] as num).toDouble(),
            right: (l['right'] as num).toDouble(),
            bottom: (l['bottom'] as num).toDouble(),
            confidence: (l['confidence'] as num).toDouble(),
          ),
      ];
      final d = BankStatementParser.parse(
        f['text'] as String,
        lines: lines,
        focusRows: (f['focus'] as List).cast<String>(),
        categories: const [
          Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
        ],
        now: DateTime(2026, 11, 5),
        defaultCurrency: 'RUB',
      );
      expect(d.isStatement, isFalse, reason: 'a receipt is one operation');
      expect(d.drafts, hasLength(1));
      final amount = d.drafts.single.amountMinor;
      expect(amount, f['expectedMinor']);
      // Never a wrong amount: either the printed total or empty for review.
      expect(amount == null || amount == f['printedTotalMinor'], isTrue);
    });
  }

  test('label tolerance: look-alikes, a missing letter, split words', () {
    for (final row in [
      'ИТОГ =100.00',
      'ИTOГ =100.00',
      'NTOГ =100.00',
      'ИТ0Г =100.00',
      'ИТОР =100.00',
      'wror =100.00',
      'И ТОГ =100.00',
      '| ИТОГО =100.00',
      'ИТОГО К ОПЛАТЕ 100,00',
      'К ОПЛАТЕ 100,00',
    ]) {
      expect(ReceiptTotal.isTotalRow(row), isTrue, reason: row);
      expect(ReceiptTotal.find([row])?.minor, 10000, reason: row);
    }
    for (final row in [
      'СУММА НДС 20% =16.67',
      'СДАЧА =5.00',
      'НАЛИЧНЫМИ =200.00',
      'Молоко 1 x 100.00 =100.00',
      'ИТОГО СКИДКА =10.00',
    ]) {
      expect(ReceiptTotal.isTotalRow(row), isFalse, reason: row);
    }
  });

  test('only the «ИТОГ» row is the amount; VAT only checks it', () {
    // No «ИТОГ» row: a VAT-consistent number is still not the amount.
    expect(
      ReceiptTotal.find([
        '=8073.10',
        'СУММА НДС 20% =1345.52',
        'НАЛИЧНЫМИ =9000.00',
        'СДАЧА =926.90',
      ]),
      isNull,
    );
    // «ИТОГ» row whose value is really the VAT (1181,18 = 7087,10 × 20/120):
    // a skewed join, left empty instead of pre-filling the VAT.
    expect(
      ReceiptTotal.find(['ИТОГ', '=1181.18', '=7087.10', '=7087.10']),
      isNull,
    );
    // 2026 rate 22 %: 1220,00 × 22/122 = 220,00.
    expect(
      ReceiptTotal.find(['ИТОГ =1220.00', 'НДС 22% =220.00'])?.evidence,
      containsAll(['label', 'vat']),
    );
    // Owner's examples: ИТОГ wins over ВСЕГО, СУММА ЧЕКА, СУММА, cash, VAT.
    expect(
      ReceiptTotal.find([
        'ВСЕГО ≡10000.00',
        'ИТОГ ≡10000.00',
        'НАЛИЧНЫМИ ≡10000.00',
        'СДАЧА ≡0.00',
        'НДС 18% ≡1525.42',
      ])?.minor,
      1000000,
    );
    expect(
      ReceiptTotal.find([
        'СУММА =2550.00',
        'ИТОГ ≡2550.00',
        'НАЛИЧНЫМИ =1000.00',
        'ЭЛЕКТРОННЫМИ =1550.00',
        'Сумма НДС 10% =231.82',
      ])?.minor,
      255000,
    );
  });

  test('several readings of the «ИТОГ» row are reconciled', () {
    // Chek correction photo: main pass read «≡» as 5, block pass is right.
    expect(
      ReceiptTotal.find(
        ['ИТОГ 52550.00) ae', 'Сумма НДС 10% =231.82'],
        focusRows: ['Wor =2550. 00'],
      )?.minor,
      255000,
    );
    // Restaurant: only the whole-page block pass read the total row.
    expect(
      ReceiptTotal.find(
        ['Бутерброд с красной икрой 250.00*1шт. =250.00'],
        focusRows: ['итог =1570.00', '№ итог | =1570.00 /'],
      )?.minor,
      157000,
    );
    // Crumpled photo: damaged «ИТОГ» digits confirmed by the cashless row.
    final damaged = ReceiptTotal.find([
      'ИТОГ. =4199_o0.',
      'БЕЗНАЛИЧНЫМИ =4199.00',
      'НДС 20% 699,83',
    ]);
    expect(damaged?.minor, 419900);
    expect(damaged?.warning, contains('Проверьте'));
    // A damaged reading without confirmation is not used.
    expect(ReceiptTotal.find(['ИТОГ. =4199_o0.']), isNull);
    // On a real phone: the main pass read only «ТОГ», the block pass read
    // the row as «ic =92 .00»; native marks that row by its height.
    expect(
      ReceiptTotal.find(
        ['Шоколад ГОРЬКИЙ', 'ТОГ', '=92 . Ш', 'НАЛИЧНЫМИ |', '=92.00'],
        focusRows: ['ic =92 .00', 'НАЛИЧНЫМИ =92 .00', '[ИТОГ] ic =92 .00'],
      )?.minor,
      9200,
    );
    // On a real phone the band re-read lost a digit («570.00»); the block
    // pass and the printed cash rows support 1570.00.
    expect(
      ReceiptTotal.find(
        ['=1570.00', '=1570.00', 'ПОЛУЧЕНО НАЛИЧНЫМИ =1600.00'],
        focusRows: ['итог =1570.00', '№ итог 570.00 /'],
      )?.minor,
      157000,
    );
    // «*» and spaced prefixes: «ИТОГ * 260.00».
    expect(ReceiptTotal.find(['ИТОГ _*260.00'])?.minor, 26000);
  });

  test('cash tendered and change are never the total', () {
    final match = ReceiptTotal.find([
      'ИТОГ =4522.80',
      'НАЛИЧНЫМИ =5000.00',
      'СДАЧА =477.20',
    ]);
    expect(match?.minor, 452280);
    expect(ReceiptTotal.find(['НАЛИЧНЫМИ =5000.00', 'СДАЧА =477.20']), isNull);
  });
}
