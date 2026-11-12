import 'dart:convert';
import 'dart:io';

import 'package:finora/domain/bank_statement_parser.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/scan_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1.55: the details page of one operation (with cashback, commission or the
/// amount in the card currency) was read as a history list and split into
/// several rows with no payee or date. The fixture is host Tesseract output
/// (bundled rus+eng models, the app's preprocessing) for bank-style screens.
void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/ocr/v155-operation-details.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  const categories = [
    Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
    Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
  ];
  ScanDocument parse(String name) {
    final screen = fixture[name] as Map<String, dynamic>;
    return BankStatementParser.parse(
      screen['text'] as String,
      lines: [
        for (final l in screen['lines'] as List)
          RecognizedLine(
            text: l['text'] as String,
            left: (l['left'] as num).toDouble(),
            top: (l['top'] as num).toDouble(),
            right: (l['right'] as num).toDouble(),
            bottom: (l['bottom'] as num).toDouble(),
            confidence: (l['confidence'] as num).toDouble(),
          ),
      ],
      categories: categories,
      now: DateTime(2026, 11, 12, 15),
      defaultCurrency: 'RUB',
    );
  }

  for (final (name, amount, payee, date, kind) in [
    (
      'tbank_purchase_dark',
      123456,
      'Пятёрочка',
      DateTime(2026, 11, 12, 14, 32),
      EntryKind.expense,
    ),
    (
      'sber_purchase_light',
      85000,
      'Перекрёсток',
      DateTime(2026, 11, 12, 18, 40),
      EntryKind.expense,
    ),
    (
      'sbp_out_light',
      500000,
      'Иван Иванович И.',
      DateTime(2026, 11, 12, 10, 5),
      null,
    ),
    (
      'salary_dark',
      8500000,
      'Зарплата',
      DateTime(2026, 11, 10),
      EntryKind.income,
    ),
  ]) {
    test('$name is one operation with its payee, date and amount', () {
      final document = parse(name);
      expect(document.isStatement, isFalse);
      final draft = document.drafts.single;
      expect(draft.amountMinor, amount);
      expect(draft.currency, 'RUB');
      expect(draft.payee, payee);
      // The status-bar clock (14:32 on every screen) is not the operation
      // time when the page shows its own.
      expect(draft.date, date);
      expect(draft.kind, kind);
    });
  }
}
