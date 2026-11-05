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

  test('fixtures are present', () => expect(fixtures, hasLength(18)));
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

  test('VAT confirms, a VAT amount never becomes the total', () {
    // 8073,10 × 20/120 = 1345,52.
    final match = ReceiptTotal.find([
      '=8073.10',
      'СУММА НДС 20% =1345.52',
      'НАЛИЧНЫМИ =9000.00',
      'СДАЧА =926.90',
    ]);
    expect(match?.minor, 807310);
    expect(match?.warning, contains('проверьте'));
    expect(
      ReceiptTotal.find(['ИТОГ', '=1181.18', '=7087.10', '=7087.10'])?.minor,
      708710,
    );
    // 2026 rate 22 %: 1220,00 × 22/122 = 220,00.
    expect(
      ReceiptTotal.find(['ИТОГ =1220.00', 'НДС 22% =220.00'])?.evidence,
      containsAll(['label', 'vat']),
    );
  });

  test('one-digit disagreement is resolved by evidence or left empty', () {
    // Payment and VAT agree on 8073,10; the label row was misread.
    expect(
      ReceiptTotal.find([
        'ИТОГ =9073.10',
        'СУММА НДС 20% =1345.52',
        'БЕЗНАЛИЧНЫМИ =8073.10',
      ])?.minor,
      807310,
    );
    // Two readings, nothing confirms either: do not guess.
    expect(ReceiptTotal.find(['ИТОГ =9073.10', '=8073.10']), isNull);
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
