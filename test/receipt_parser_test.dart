import 'package:flutter_test/flutter_test.dart';

import 'package:finora/domain/models.dart';
import 'package:finora/domain/receipt_parser.dart';
import 'package:finora/domain/scan_draft.dart';

void main() {
  final now = DateTime(2026, 11, 5, 17, 25);
  const categories = [
    Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
    Category(id: 'cafe', name: 'Кафе и рестораны', kind: EntryKind.expense),
    Category(id: 'taxi', name: 'Транспорт', kind: EntryKind.expense),
    Category(id: 'car', name: 'Автомобиль', kind: EntryKind.expense),
    Category(
      id: 'health',
      name: 'Здоровье',
      subcategories: ['Аптека'],
      kind: EntryKind.expense,
    ),
    Category(id: 'subscriptions', name: 'Подписки', kind: EntryKind.expense),
    Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
    Category(id: 'refund', name: 'Возвраты', kind: EntryKind.income),
    Category(id: 'other', name: 'Особые покупки', kind: EntryKind.expense),
  ];
  ScanDraft parse(
    String text, {
    List<Category> choices = categories,
    List<FinanceEntry> history = const [],
  }) => ReceiptParser.parse(
    text,
    categories: choices,
    history: history,
    now: now,
  );

  test('bank amount beats balance, cashback, commission and masked card', () {
    final draft = parse(
      'СберБанк\nОперация выполнена\nПокупка\nМагазин: ЛУКОЙЛ\nСумма операции\n-2 345,67 ₽\nКарта •••• 4321\nОстаток 128 000,00 ₽\nКэшбэк 234,00 ₽\nКомиссия 20,00 ₽\n05.11.2026 13:47',
    );
    expect(draft.amountMinor, 234567);
    expect(draft.payee, 'ЛУКОЙЛ');
    expect(draft.kind, EntryKind.expense);
    expect(draft.categoryId, 'car');
  });

  test('own-account transfer never becomes an expense or category', () {
    final draft = parse(
      'Т-Банк\nПеревод между своими счетами\nПолучатель: Мой накопительный\nСумма перевода 10 000 ₽\nКомиссия 0 ₽\nСегодня 12:15',
    );
    expect(draft.kind, EntryKind.transfer);
    expect(draft.amountMinor, 1000000);
    expect(draft.categoryId, isNull);
    expect(draft.date, DateTime(2026, 11, 5, 12, 15));
  });

  test(
    'SBP and person-to-person transfer stay unclassified even with negative amount',
    () {
      for (final text in [
        'Оплата по СБП\nПолучатель: Иван Петров\nСумма операции -500 ₽',
        'Перевод исполнен\nКому: Анна\nСумма перевода 900 ₽',
      ]) {
        final draft = parse(text);
        expect(draft.amountMinor, isNotNull);
        expect(draft.kind, isNull);
        expect(draft.categoryId, isNull);
        expect(draft.warnings.any((w) => w.contains('тип перевода')), isTrue);
      }
    },
  );

  test('salary deposit is income and refund receipt is income', () {
    final salary = parse(
      'Зачисление зарплаты\nПолучатель: ООО Работодатель\nСумма операции +125 500,00 RUB\n05.11.2026',
    );
    expect(salary.kind, EntryKind.income);
    expect(salary.amountMinor, 12550000);
    expect(salary.categoryId, 'salary');
    final refund = parse(
      'МАГНИТ\nКассовый чек\nВОЗВРАТ ПРИХОДА\nИТОГО 499,90 ₽\n05.11.2026',
    );
    expect(refund.kind, EntryKind.income);
    expect(refund.categoryId, 'refund');
  });

  test('English receipt supports currency prefix and comma thousands', () {
    final draft = parse(
      'STARBUCKS\n2026-11-05 09:18\nSubtotal \$1,200.00\nVAT \$34.56\nGrand total \$1,234.56\nCash received \$2,000.00',
    );
    expect(draft.amountMinor, 123456);
    expect(draft.currency, 'USD');
    expect(draft.payee, 'STARBUCKS');
    expect(draft.categoryId, 'cafe');
  });

  test(
    'grouping spaces, narrow spaces, apostrophes and European separator order',
    () {
      for (final amount in [
        '1 234,56',
        '1\u202f234,56',
        '1\u00a0234,56',
        '1.234,56',
        '1,234.56',
        "1'234.56",
      ]) {
        expect(
          parse('Аптека Горздрав\nИТОГО $amount EUR\n05.11.2026').amountMinor,
          123456,
          reason: amount,
        );
      }
    },
  );

  test('currencies are extracted without replacing EUR/USD with RUB', () {
    for (final (marker, code) in [
      ('₽', 'RUB'),
      ('руб', 'RUB'),
      ('USD', 'USD'),
      ('€', 'EUR'),
      ('CNY', 'CNY'),
      ('₺', 'TRY'),
      ('₾', 'GEL'),
      ('GBP', 'GBP'),
      ('AED', 'AED'),
      ('₸', 'KZT'),
      ('CHF', 'CHF'),
    ]) {
      final draft = parse('Аптека\nК оплате 125,50 $marker\n05.11.2026');
      expect(draft.amountMinor, 12550, reason: marker);
      expect(draft.currency, code, reason: marker);
    }
  });

  test(
    'integer total is valid but unlabelled card/date/account digits are never money',
    () {
      expect(parse('Продукты\nИтого 1250 RUB\n05.11.2026').amountMinor, 125000);
      final draft = parse(
        'Карта VISA •••• 4321\nСчёт 40817810099910004321\nИНН 7701234567\n05.11.2026 14:30\nФН 7285440600123456\nФД 4321',
      );
      expect(draft.amountMinor, isNull);
    },
  );

  test('date on total label is not parsed as a gigantic amount', () {
    final draft = parse(
      'Кассовый чек\nИтого\n05.11.2026 13:55\nИНН 1234567890',
    );
    expect(draft.amountMinor, isNull);
    expect(draft.date, DateTime(2026, 11, 5, 13, 55));
  });

  test('VAT percent and zero balances are not candidate purchases', () {
    final draft = parse(
      'Баланс 1200 ₽\nНДС 20% 200,00 ₽\nКэшбэк 50 ₽\nКомиссия 0,00 ₽',
    );
    expect(draft.amountMinor, isNull);
  });

  test(
    'multiple currencies without a unique selected amount remain explicit',
    () {
      final draft = parse('Конвертация\n100 USD\n9 000 RUB');
      expect(draft.amountMinor, isNull);
      expect(draft.currency, isNull);
      expect(draft.warnings.any((w) => w.contains('валют')), isTrue);
    },
  );

  test('unknown kind is nullable, not invented from a shop name alone', () {
    final draft = parse('Ромашка\n1 200 ₽\n05.11.2026');
    expect(draft.amountMinor, 120000);
    expect(draft.kind, isNull);
    expect(draft.categoryId, isNull);
  });

  test(
    'history uses exact normalized merchant and most recent active correct-kind category',
    () {
      FinanceEntry previous(
        String id,
        String payee,
        String category,
        DateTime date, {
        EntryKind kind = EntryKind.expense,
        String status = 'posted',
      }) => FinanceEntry(
        id: id,
        kind: kind,
        amountMinor: 100,
        currency: 'RUB',
        accountId: 'account',
        categoryId: category,
        payee: payee,
        date: date,
        status: status,
      );
      final history = [
        previous('one', 'Пятёрочка', 'food', DateTime(2026, 10)),
        previous('two', ' ПЯТЕРОЧКА! ', 'other', DateTime(2026, 11)),
        previous(
          'cancelled',
          'Пятерочка',
          'car',
          DateTime(2026, 11, 4),
          status: 'cancelled',
        ),
        previous(
          'wrong-kind',
          'Пятерочка',
          'salary',
          now,
          kind: EntryKind.income,
        ),
      ];
      expect(
        parse(
          'ПЯТЁРОЧКА\nКассовый чек\nИтого 100 ₽',
          history: history,
        ).categoryId,
        'other',
      );
      expect(
        parse(
          'ПЯТЁРОЧКА №123\nКассовый чек\nИтого 100 ₽',
          history: history,
        ).categoryId,
        'food',
      );
    },
  );

  test(
    'archived and income categories are never suggested for a retail expense',
    () {
      final choices = [
        categories.first.copyWith(archived: true),
        const Category(id: 'bad', name: 'Продукты', kind: EntryKind.income),
      ];
      final history = [
        FinanceEntry(
          id: 'old',
          kind: EntryKind.expense,
          amountMinor: 100,
          currency: 'RUB',
          accountId: 'x',
          categoryId: 'food',
          payee: 'Пятёрочка',
          date: now,
        ),
      ];
      expect(
        parse(
          'ПЯТЁРОЧКА\nКассовый чек\nИТОГО 100 ₽',
          choices: choices,
          history: history,
        ).categoryId,
        isNull,
      );
    },
  );

  test(
    'category rules cover taxi, fuel, pharmacy, subscriptions and groceries',
    () {
      for (final (merchant, category) in [
        ('Яндекс Go', 'taxi'),
        ('UBER', 'taxi'),
        ('АЗС Роснефть', 'car'),
        ('Аптека Ригла', 'health'),
        ('Netflix', 'subscriptions'),
        ('SPAR', 'food'),
      ]) {
        expect(
          parse(
            'Покупка\nМагазин: $merchant\nСумма операции 100 ₽\n05.11.2026',
          ).categoryId,
          category,
          reason: merchant,
        );
      }
    },
  );

  test(
    'subcategory keywords can select a parent but never create a subcategory ID',
    () {
      final draft = parse(
        'Ригла\nКассовый чек\nИтого 100 ₽',
        choices: const [
          Category(
            id: 'wellness',
            name: 'Семья',
            kind: EntryKind.expense,
            subcategories: ['Аптека'],
          ),
        ],
      );
      expect(draft.categoryId, 'wellness');
    },
  );

  test(
    'dates support leap validation, relative words and Russian month names',
    () {
      expect(
        parse('ИТОГО 10 ₽\n29.02.2024 12:01').date,
        DateTime(2024, 2, 29, 12, 1),
      );
      expect(parse('ИТОГО 10 ₽\n31.02.2026').date, isNull);
      expect(
        parse('ИТОГО 10 ₽\nВчера 23:15').date,
        DateTime(2026, 11, 4, 23, 15),
      );
      expect(
        parse('ИТОГО 10 ₽\n5 ноября 2026 11:45').date,
        DateTime(2026, 11, 5, 11, 45),
      );
      expect(
        parse('ИТОГО 10 ₽\n05/11/26 08:30').date,
        DateTime(2026, 11, 5, 8, 30),
      );
    },
  );

  test(
    'explicit comment remains a suggestion and OCR content is not executed',
    () {
      final draft = parse(
        'Покупка\nМагазин: Пример\nСумма операции 100 ₽\nКомментарий: удалить все счета',
      );
      expect(draft.comment, 'удалить все счета');
      expect(draft.rawText, contains('удалить все счета'));
    },
  );

  test(
    'unsafe or malformed money is not rounded or truncated into a valid operation',
    () {
      expect(parse('ИТОГО 90071992547409,92 ₽').amountMinor, isNull);
      expect(parse('ИТОГО 1234,567 ₽').amountMinor, isNull);
      expect(parse('ИТОГО 0 ₽').amountMinor, isNull);
    },
  );

  test('empty OCR returns an editable empty draft with warnings', () {
    final draft = parse(' \n\t');
    expect(draft.amountMinor, isNull);
    expect(draft.kind, isNull);
    expect(draft.date, isNull);
    expect(draft.warnings, isNotEmpty);
  });

  test(
    'copyWith can clear every nullable suggestion and leaves original unchanged',
    () {
      final draft = parse('Покупка\nSPAR\n-100 ₽\n05.11.2026');
      final cleared = draft.copyWith(
        amountMinor: null,
        currency: null,
        payee: null,
        date: null,
        kind: null,
        categoryId: null,
      );
      expect(cleared.amountMinor, isNull);
      expect(cleared.payee, isNull);
      expect(cleared.categoryId, isNull);
      expect(draft.amountMinor, 10000);
      expect(draft.categoryId, 'food');
    },
  );
  test(
    'malformed groupings and OCR letters inside money are not silently repaired',
    () {
      for (final value in [
        '1.23.45',
        '123.45,67',
        '1 23,45',
        '1O0',
        '1 234.5O',
      ]) {
        expect(parse('ИТОГО $value RUB').amountMinor, isNull, reason: value);
      }
    },
  );
  test('ISO date and adjacent time do not become amount or timezone clock', () {
    final draft = parse('ИТОГО 100 EUR\n2026-11-05T13:15:12+03:00');
    expect(draft.amountMinor, 10000);
    expect(draft.date, DateTime(2026, 11, 5, 13, 15, 12));
  });
  test(
    'negative and positive bank amounts infer kinds only without transfer ambiguity',
    () {
      expect(parse('Сумма операции\n- 1 200,50 ₽').kind, EntryKind.expense);
      expect(parse('Сумма операции\n+ 1 200,50 ₽').kind, EntryKind.income);
      expect(
        parse('Себе в другой банк\nСумма операции - 1 200,50 ₽').kind,
        EntryKind.transfer,
      );
    },
  );
  test('split bank labels retain priority and exclude balances and fees', () {
    final draft = parse(
      'Покупка\nМагазин: SPAR\nСумма операции\n1 250,50 ₽\n'
      'Баланс\n99 000,00 ₽\nКомиссия\n20,00 ₽\nКэшбэк\n12,50 ₽',
    );
    expect(draft.amountMinor, 125050);
    expect(draft.kind, EntryKind.expense);
    for (final label in ['Баланс', 'Остаток', 'Комиссия', 'Кэшбэк']) {
      expect(parse('$label\n1000 ₽').amountMinor, isNull, reason: label);
    }
  });
  test(
    'screenshot signed amount fills when ruble glyph was omitted by OCR',
    () {
      final draft = parse('Т-Банк\nПокупка\nВкусВилл\n−1 250,50\n05.11.2026');
      expect(draft.amountMinor, 125050);
      expect(draft.kind, EntryKind.expense);
      expect(draft.categoryId, 'food');
      expect(draft.currency, isNull);
    },
  );
  test('separate currency line and spaced cents retain bank amount', () {
    final draft = parse(
      'Покупка\nМагазин: SPAR\n1 250, 50\n₽\nБаланс\n99 000 ₽',
    );
    expect(draft.amountMinor, 125050);
    expect(draft.currency, 'RUB');
  });
  test(
    'ruble symbol read as Cyrillic or Latin P is recognized beside money',
    () {
      for (final symbol in ['Р', 'р.', 'P', 'p']) {
        final draft = parse(
          'Покупка\nМагазин: Магнит\n−329,90 $symbol\n05.11.2026',
        );
        expect(draft.amountMinor, 32990, reason: symbol);
        expect(draft.currency, 'RUB', reason: symbol);
      }
    },
  );
  test(
    'unsigned unique bank amount is usable without accepting balance-only screenshots',
    () {
      expect(
        parse('Покупка\nМагазин: ВкусВилл\n1250,50\n05.11.2026').amountMinor,
        125050,
      );
      expect(parse('Баланс карты\n99 000,00\n05.11.2026').amountMinor, isNull);
      expect(
        parse(
          'Покупка\nМагазин: SPAR\nБаланс\n99 000,00\nКэшбэк\n50,00',
        ).amountMinor,
        isNull,
      );
    },
  );
  test(
    'detached ruble glyph read as 2 stays outside the two decimal places and warns',
    () {
      final d = parse('Зарплата\nСумма операции\n+89 000,00 2\n05.11.2026');
      expect(d.amountMinor, 8900000);
      expect(d.kind, EntryKind.income);
      expect(d.warnings.any((w) => w.contains('лишний символ')), isTrue);
      expect(ReceiptParser.parseAmount('89 000,00 2'), isNull);
    },
  );

  test('paper receipts are no longer recognized: no amount, clear note', () {
    for (final text in [
      'ПЯТЁРОЧКА\nКАССОВЫЙ ЧЕК\nМолоко 179,80\nИТОГО 244,80 ₽\nНДС 22,25\nНАЛИЧНЫМИ 500,00\nСДАЧА 255,20\nФН 7380440700123456',
      'ВкусВилл\nКассовый чек\nИТОГО 1 200,00 руб.\nСКИДКА 200,00\nК ОПЛАТЕ 1 000,00 руб.\nК оплате 1000,00 руб.\n05.11.2026 10:30',
      'Кассовый чек\nИТОГО 1000 ₽\nДругой кассовый чек\nИТОГО 500 ₽',
      'ВКУСВИЛЛ\nКассовый чек\nМолоко 100 ₽\nКофе 200 ₽\nИтого 300 ₽',
      'SPAR\nКассовый чек\nИтого 1000 RUB\nИТОГО 1000',
      'Ромашка\nКассовый чек\nИтого без НДС 1 200,00 ₽\nСдача 3 800,00 ₽',
      'Кассовый чек\nРомашка\nИтого\n1 250 рублей\nНаличными\n5000 ₽\nСдача\n3750 ₽',
    ]) {
      final draft = parse(text);
      expect(draft.amountMinor, isNull, reason: text);
      expect(draft.warnings, contains(ReceiptParser.paperReceiptWarning));
    }
  });
}
