import 'dart:convert';
import 'dart:io';
import 'package:finora/domain/bank_statement_parser.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/scan_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 5, 16);
  const categories = [
    Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
    Category(id: 'cafe', name: 'Кафе и рестораны', kind: EntryKind.expense),
    Category(id: 'taxi', name: 'Транспорт', kind: EntryKind.expense),
    Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
    Category(id: 'other', name: 'Прочее', kind: EntryKind.expense),
    Category(id: 'custom', name: 'Личное', kind: EntryKind.expense),
    Category(id: 'car', name: 'Автомобиль', kind: EntryKind.expense),
    Category(id: 'health', name: 'Здоровье', kind: EntryKind.expense),
    Category(
      id: 'archived',
      name: 'Архив',
      kind: EntryKind.expense,
      archived: true,
    ),
  ];
  ScanDocument parse(
    String text, {
    List<RecognizedLine> lines = const [],
    List<FinanceEntry> history = const [],
    String? currency,
  }) => BankStatementParser.parse(
    text,
    lines: lines,
    categories: categories,
    history: history,
    now: now,
    defaultCurrency: currency,
  );
  RecognizedLine line(
    String text,
    double x,
    double y, {
    double right = .95,
    double confidence = .95,
  }) => RecognizedLine(
    text: text,
    left: x,
    top: y,
    right: right,
    bottom: y + .025,
    confidence: confidence,
  );
  test('bank category labels can select any active custom category', () {
    final d = parse(
      'Операции\nСегодня\nSome Shop -250 ₽\nЛичное\nВкусВилл -100 ₽',
    );
    expect(d.drafts.first.categoryId, 'custom');
    expect(d.drafts.last.categoryId, 'food');
  });
  test(
    'T bank history shares Russian date headers and fills grocery cafe salary',
    () {
      final d = parse('''История операций
5 ноября 2026
ВкусВилл -1 250,50 ₽
Продукты
Кофейня Coffee Bean -350 ₽
Кафе и рестораны
Вчера
Зарплата +89 000 ₽
Баланс 94 800 ₽
Кэшбэк 125 ₽''');
      expect(d.isStatement, isTrue);
      expect(d.drafts, hasLength(3));
      expect(d.drafts.map((d) => d.amountMinor), [125050, 35000, 8900000]);
      expect(d.drafts.map((d) => d.kind), [
        EntryKind.expense,
        EntryKind.expense,
        EntryKind.income,
      ]);
      expect(d.drafts.map((d) => d.categoryId), ['food', 'cafe', 'salary']);
      expect(d.drafts.map((d) => d.date), [
        DateTime(2026, 11, 5),
        DateTime(2026, 11, 5),
        DateTime(2026, 11, 4),
      ]);
      expect(d.drafts.every((d) => d.currency == 'RUB'), isTrue);
    },
  );
  test(
    'separate amount cells are paired by geometry rather than column reading order',
    () {
      final lines = [
        line('Все операции', .05, .03),
        line('05.11.2026', .05, .10),
        line('ВкусВилл', .07, .20, right: .45),
        line('Кофейня', .07, .35, right: .45),
        line('Зарплата', .07, .50, right: .45),
        line('-1 250,50 ₽', .65, .201),
        line('-350 ₽', .70, .351),
        line('+89 000 ₽', .62, .501),
      ];
      final d = parse(lines.map((l) => l.text).join('\n'), lines: lines);
      expect(d.drafts, hasLength(3));
      expect(d.drafts.map((d) => d.payee), ['ВкусВилл', 'Кофейня', 'Зарплата']);
      expect(d.drafts.map((d) => d.amountMinor), [125050, 35000, 8900000]);
    },
  );
  test('Sber stacked merchant category then amount retains each operation', () {
    final d = parse('''Операции
Сегодня
Пятёрочка
Продукты
−329,90 Р
Яндекс Go
Транспорт
−450,00 p
Вчера
Зачисление зарплаты
+80 000,00 ₽''');
    expect(d.drafts, hasLength(3));
    expect(d.drafts.map((d) => d.payee), [
      'Пятёрочка',
      'Яндекс Go',
      'Зачисление зарплаты',
    ]);
    expect(d.drafts.map((d) => d.categoryId), ['food', 'taxi', 'salary']);
    expect(d.drafts.map((d) => d.amountMinor), [32990, 45000, 8000000]);
  });
  test(
    'dated statement table strips dates and keeps independent time amounts',
    () {
      final d = parse('''Выписка по карте
Дата Описание Сумма
05.11.2026 09:30 ВкусВилл -1 250,50 RUB
04.11.2026 15:20 Coffee House -300,00 RUB
Начальный остаток 100 000,00 RUB
Конечный остаток 98 449,50 RUB''');
      expect(d.drafts, hasLength(2));
      expect(d.drafts.map((d) => d.payee), ['ВкусВилл', 'Coffee House']);
      expect(d.drafts.map((d) => d.date), [
        DateTime(2026, 11, 5, 9, 30),
        DateTime(2026, 11, 4, 15, 20),
      ]);
    },
  );
  test(
    'identical legitimate rows are preserved instead of deduplicating transactions',
    () {
      final d = parse('Операции\nСегодня\nКофейня -150 ₽\nКофейня -150 ₽');
      expect(d.drafts, hasLength(2));
      expect(d.drafts.every((d) => d.amountMinor == 15000), isTrue);
    },
  );
  test(
    'fiscal receipt never turns product line items into separate operations',
    () {
      final d = parse(
        'ПЯТЁРОЧКА\nКассовый чек\nМолоко 179,80 ₽\nХлеб 65 ₽\nИТОГО 244,80 ₽\nНДС 22,25',
      );
      expect(d.isStatement, isFalse);
      expect(d.drafts, hasLength(1));
      // Paper receipts are not recognized any more: one empty draft.
      expect(d.drafts.single.amountMinor, isNull);
    },
  );
  test('simple receipt with total is protected even without fiscal marker', () {
    final d = parse('SPAR\nМолоко 50 ₽\nХлеб 30 ₽\nИтого 80 ₽');
    expect(d.isStatement, isFalse);
    expect(d.drafts.single.amountMinor, 8000);
  });
  test('transfer stays ambiguous unless own accounts explicitly identified', () {
    final d = parse(
      'Операции\nСегодня\nПеревод Анне -500 ₽\nПеревод между своими счетами -2000 ₽',
    );
    expect(d.drafts, hasLength(2));
    expect(d.drafts.first.kind, isNull);
    expect(d.drafts.first.categoryId, isNull);
    expect(d.drafts.last.kind, EntryKind.transfer);
    expect(d.drafts.last.categoryId, isNull);
  });
  test(
    'unknown currency stays explicit and is not replaced with account RUB',
    () {
      final d = parse(
        'Операции\nСегодня\nBook Store -100 JPY\nCoffee Shop -12.50 USD',
        currency: 'RUB',
      );
      expect(d.drafts, hasLength(2));
      expect(d.drafts.map((d) => d.currency), ['JPY', 'USD']);
      expect(d.drafts.map((d) => d.amountMinor), [10000, 1250]);
    },
  );
  test(
    'missing currency can use account currency but emits a review warning',
    () {
      final d = parse(
        'Операции\nСегодня\nВкусВилл -1200,50\nКофейня -300,00',
        currency: 'EUR',
      );
      expect(d.drafts, hasLength(2));
      expect(d.drafts.every((d) => d.currency == 'EUR'), isTrue);
      expect(
        d.drafts.every(
          (d) => d.warnings.any((w) => w.contains('Предложена валюта')),
        ),
        isTrue,
      );
    },
  );
  test(
    'split metadata amounts are excluded without dropping a genuine fee operation',
    () {
      final d = parse(
        'Операции\nСегодня\nВкусВилл -1000 ₽\nБаланс\n9000 ₽\nКомиссия\n10 ₽\nКофейня -100 ₽\nКомиссия за обслуживание -299 ₽',
      );
      expect(d.drafts, hasLength(3));
      expect(d.drafts.map((d) => d.amountMinor), [100000, 10000, 29900]);
    },
  );
  test('merchant history uses most recent active correct-kind category', () {
    final h = [
      FinanceEntry(
        id: 'one',
        kind: EntryKind.expense,
        amountMinor: 100,
        currency: 'RUB',
        accountId: 'card',
        categoryId: 'custom',
        date: DateTime(2026, 11, 4),
        payee: 'SOME STORE',
      ),
    ];
    final d = parse(
      'Операции\nСегодня\nSome Store -123 ₽\nВкусВилл -500 ₽',
      history: h,
    );
    expect(d.drafts.first.categoryId, 'custom');
    expect(d.drafts.last.categoryId, 'food');
  });
  test('unreliable lost column order does not assign arbitrary merchant', () {
    final d = parse('Операции\nСегодня\nВкусВилл\nКофейня\n-100 ₽\n-200 ₽');
    expect(d.drafts, hasLength(2));
    expect(d.drafts.map((d) => d.payee), [null, null]);
    expect(
      d.drafts.first.warnings.any((w) => w.contains('получателя')),
      isTrue,
    );
  });
  test('low-confidence visual row and cancelled row force user review', () {
    final lines = [
      line('Операции', .05, .03),
      line('Сегодня', .05, .10),
      line('ВкусВилл -100 ₽', .05, .20, confidence: .40),
      line('Отменено Coffee House -200 ₽', .05, .35),
    ];
    final d = parse(lines.map((l) => l.text).join('\n'), lines: lines);
    expect(
      d.drafts.first.warnings.any((w) => w.contains('неуверенно')),
      isTrue,
    );
    expect(d.drafts.last.kind, isNull);
    expect(d.drafts.last.warnings.any((w) => w.contains('отменённая')), isTrue);
  });
  test('invalid geometry is ignored and text path still parses safely', () {
    final d = parse(
      'Операции\nСегодня\nВкусВилл -100 ₽\nКофейня -200 ₽',
      lines: [line('Bogus', double.nan, .2)],
    );
    expect(d.drafts, hasLength(2));
  });
  test('zero values and percentages are not operations', () {
    final d = parse(
      'Операции\nСегодня\nВкусВилл -100 ₽\nКофейня -200 ₽\nКэшбэк 5%\nПроцент 12,50%\nZero 0 ₽',
    );
    expect(d.drafts, hasLength(2));
  });
  for (final brightness in ['dark', 'light']) {
    test(
      'actual host OCR $brightness wire retains all five bank rows including ruble glyph artifacts',
      () {
        final wire =
            jsonDecode(
                  File(
                    'test/fixtures/ocr/v15-$brightness-wire.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        final rows = (wire['lines'] as List)
            .map(
              (r) => RecognizedLine(
                text: r['text'] as String,
                left: (r['left'] as num).toDouble(),
                top: (r['top'] as num).toDouble(),
                right: (r['right'] as num).toDouble(),
                bottom: (r['bottom'] as num).toDouble(),
                confidence: (r['confidence'] as num).toDouble(),
              ),
            )
            .toList();
        final d = parse(wire['text'] as String, lines: rows, currency: 'RUB');
        expect(d.isStatement, isTrue);
        expect(d.drafts, hasLength(5));
        expect(d.drafts.map((d) => d.amountMinor), [
          125050,
          287580,
          73420,
          8900000,
          36000,
        ]);
        expect(d.drafts.map((d) => d.kind), [
          EntryKind.expense,
          EntryKind.expense,
          EntryKind.expense,
          EntryKind.income,
          EntryKind.expense,
        ]);
        expect(d.drafts.map((d) => d.categoryId), [
          'food',
          'car',
          'health',
          'salary',
          'cafe',
        ]);
        expect(d.drafts.every((d) => d.currency == 'RUB'), isTrue);
        expect(d.drafts.every((d) => d.date == DateTime(2026, 11, 5)), isTrue);
        if (brightness == 'dark') {
          expect(
            d.drafts[3].warnings.any((w) => w.contains('лишний символ')),
            isTrue,
          );
        }
      },
    );
  }
  test('partial numeric date header is not mistaken for an amount', () {
    final d = parse('Операции\n05.11\nВкусВилл -100 ₽\n04.11\nКофейня -200 ₽');
    expect(d.drafts, hasLength(2));
    expect(d.drafts.map((d) => d.date), [
      DateTime(2026, 11, 5),
      DateTime(2026, 11, 4),
    ]);
  });
  test(
    'standalone decimal after a merchant remains an amount rather than a date header',
    () {
      final d = parse('Операции\nСегодня\nВкусВилл\n5.11\nКофейня\n7.11');
      expect(d.drafts, hasLength(2));
      expect(d.drafts.map((d) => d.amountMinor), [511, 711]);
      expect(d.drafts.map((d) => d.date), [
        DateTime(2026, 11, 5),
        DateTime(2026, 11, 5),
      ]);
    },
  );
}
