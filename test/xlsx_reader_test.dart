import 'dart:io';

import 'package:finora/domain/foreign_csv.dart';
import 'package:finora/domain/xlsx_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 7: an Excel export is read into CSV for the usual import.
void main() {
  final bytes = File('test/fixtures/bank_export.xlsx').readAsBytesSync();

  test('cells, shared and inline strings, dates', () {
    expect(XlsxReader.looksLikeXlsx(bytes), isTrue);
    final rows = XlsxReader.readRows(bytes);
    expect(rows.first, ['Дата', 'Описание', 'Сумма', 'Категория']);
    // 46310 is 2026-10-15 in Excel's calendar.
    expect(rows[1], ['15.10.2026', 'Пятёрочка', '-450.5', 'Продукты']);
    expect(rows[2][0], '16.10.2026 12:00');
    expect(rows[2][1], 'Зарплата');
    expect(rows[2].length, 3);
    // A gap stays a gap; escapes are undone.
    expect(rows[3], ['17.10.2026', 'A&B "test"', '', '-15']);
  });

  test('the CSV goes through the existing import', () {
    final csv = XlsxReader.toCsv(bytes);
    expect(csv.split('\n'), hasLength(4));
    expect(csv, contains('"A&B ""test"""'));
    final table = ForeignCsv.read(csv);
    expect(table, isNotNull);
  });

  test('not a spreadsheet is refused with a reason', () {
    expect(
      () => XlsxReader.readRows(
        File('test/fixtures/finora_ai_parity.json').readAsBytesSync(),
      ),
      throwsFormatException,
    );
  });
}
