import 'dart:io';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final available = File('/usr/bin/tesseract').existsSync();
  for (final fixture in ['receipt', 'bank']) {
    test(
      'bundled rus+eng models recognize $fixture image through a real OCR engine',
      () async {
        final result = await Process.run('/usr/bin/tesseract', [
          'test/fixtures/ocr/$fixture.png',
          'stdout',
          '--tessdata-dir',
          'assets/ocr/tessdata',
          '-l',
          'rus+eng',
          '--psm',
          '3',
          '--dpi',
          '300',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final draft = ReceiptParser.parse(
          '${result.stdout}',
          categories: const [
            Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
          ],
        );
        // Paper receipts are no longer recognized: no amount, a clear note.
        expect(draft.amountMinor, fixture == 'receipt' ? isNull : 125050);
        if (fixture == 'receipt') {
          expect(draft.warnings, contains(ReceiptParser.paperReceiptWarning));
          return;
        }
        expect(draft.currency, 'RUB');
        expect(draft.categoryId, 'food');
        expect(draft.kind, EntryKind.expense);
        expect(draft.payee, fixture == 'receipt' ? 'ПЯТЁРОЧКА' : 'ВкусВилл');
        expect(draft.date?.year, 2026);
        expect(draft.date?.month, 11);
        expect(draft.date?.day, 5);
      },
      skip: available
          ? false
          : 'Optional host Tesseract executable is not installed. Native Android validation is separate.',
    );
  }
}
