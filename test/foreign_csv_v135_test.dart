import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/foreign_csv.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/foreign_import_screen.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

const zen =
    'date;categoryName;payee;comment;outcomeAccountName;outcome;'
    'outcomeCurrencyShortTitle;incomeAccountName;income;'
    'incomeCurrencyShortTitle;createdDate;changedDate;qrCode\n'
    '2026-11-01;Продукты;Пятёрочка;;Тинькофф;1250.50;RUB;Тинькофф;0;RUB;'
    '2026-11-01 10:00:00;2026-11-01 10:00:00;\n'
    '2026-11-02;Зарплата;ООО Ромашка;аванс;Тинькофф;0;RUB;Тинькофф;85000;RUB;'
    '2026-11-02 10:00:00;2026-11-02 10:00:00;\n'
    '2026-11-03;;;;Тинькофф;10000;RUB;Наличные;10000;RUB;;;\n'
    '2026-11-04;;;;Тинькофф;9000;RUB;Доллары;100;USD;;;\n';

const coinKeeper =
    '"Данные","Тип","Из","В","Метки","Сумма","Валюта","Сумма в валюте",'
    '"Валюта","Повторение","Примечание"\r\n'
    '"07.11.2026","Расход","Карта","Кафе","кофе, утро","350","RUB","350",'
    '"RUB","Нет","латте"\r\n'
    '"06.11.2026","Доход","Зарплата","Карта","","50 000","RUB","50 000",'
    '"RUB","Нет",""\r\n'
    '"05.11.2026","Перевод","Карта","Наличные","","2 000","RUB","2 000",'
    '"RUB","Нет",""\r\n';

const moneyManager =
    'Date,Account,Category,Subcategory,Note,Amount,Income/Expense,'
    'Description,Currency\n'
    '11/07/2026 14:30:00,Cash,Food,Lunch,Burger,12.50,Expense,,USD\n'
    '11/13/2026,Cash,Salary,,,"1,500.00",Income,,USD\n'
    '11/14/2026,Cash,Card,,,40.00,Transfer-Out,,USD\n'
    '11/14/2026,Card,Cash,,,40.00,Transfer-In,,USD\n';

const monefy =
    'date,account,category,amount,currency,converted amount,currency,'
    'description\n'
    '07/11/2026,Наличные,Еда,-450,RUB,-450,RUB,Обед\n'
    '08/11/2026,Наличные,Зарплата,30000,RUB,30000,RUB,\n';

const tbank =
    '"Дата операции";"Дата платежа";"Номер карты";"Статус";"Сумма операции";'
    '"Валюта операции";"Сумма платежа";"Валюта платежа";"Кэшбэк";"Категория";'
    '"MCC";"Описание";"Бонусы (включая кэшбэк)";'
    '"Округление на инвесткопилку";"Сумма операции с округлением"\n'
    '"07.11.2026 18:22:10";"07.11.2026";"*1234";"OK";"-1 234,56";"RUB";'
    '"-1 234,56";"RUB";"";"Супермаркеты";"5411";"Пятёрочка";"12,00";"0,00";'
    '"1 234,56"\n'
    '"06.11.2026 10:00:00";"06.11.2026";"*1234";"FAILED";"-500,00";"RUB";'
    '"-500,00";"RUB";"";"Кафе";"5814";"Кофейня";"0,00";"0,00";"500,00"\n'
    '"05.11.2026 09:00:00";"05.11.2026";"";"OK";"50 000,00";"RUB";'
    '"50 000,00";"RUB";"";"Пополнения";"";"Перевод от Ивана";"0,00";"0,00";'
    '"50 000,00"\n'
    '"04.11.2026 12:00:00";"04.11.2026";"*1234";"OK";"-10,00";"USD";'
    '"-950,00";"RUB";"";"Сервисы";"5734";"Steam";"0,00";"0,00";"10,00"\n';

/// Bytes in Windows-1251, built from the decoder itself.
List<int> cp1251Bytes(String text) {
  final table = <int, int>{
    for (var b = 0; b < 256; b++) ForeignCsv.cp1251([b]).codeUnitAt(0): b,
  };
  return [for (final ch in text.codeUnits) table[ch]!];
}

FinanceData base() => const FinanceData(
  accounts: [
    Account(id: 'tink', name: 'Тинькофф', openingMinor: 100000),
    Account(id: 'cash', name: 'Наличные'),
  ],
  categories: [
    Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
    Category(id: 'other', name: 'Другое', kind: EntryKind.expense),
    Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
  ],
  members: [Member(id: 'me', name: 'Я')],
  preferences: AppPreferences(),
  demo: false,
);

void main() {
  var n = 0;
  String id() => 'id${n++}';

  ForeignParse parseOf(String text) {
    final t = ForeignCsv.read(text);
    return ForeignCsv.rows(t, t.roles);
  }

  group('formats', () {
    test('Дзен-мани: расход, доход, перевод, перевод в другой валюте', () {
      final t = ForeignCsv.read(zen);
      expect(t.format, 'Дзен-мани');
      expect(t.delimiter, ';');
      final p = ForeignCsv.rows(t, t.roles);
      expect(p.rows.length, 4);
      final r = p.rows;
      expect(r[0].kind, EntryKind.expense);
      expect(r[0].amountMinor, 125050);
      expect(r[0].category, 'Продукты');
      expect(r[0].payee, 'Пятёрочка');
      expect(r[0].account, 'Тинькофф');
      expect(r[1].kind, EntryKind.income);
      expect(r[1].amountMinor, 8500000);
      expect(r[1].note, 'аванс');
      expect(r[2].kind, EntryKind.transfer);
      expect(r[2].toAccount, 'Наличные');
      expect(r[3].kind, EntryKind.transfer);
      expect(r[3].toAmountMinor, 10000);
      expect(r[3].toCurrency, 'USD');
      expect(r[0].date, DateTime(2026, 11, 1, 12));
    });

    test('CoinKeeper: «Из» и «В» — счёт и категория', () {
      final t = ForeignCsv.read(coinKeeper);
      expect(t.format, 'CoinKeeper');
      final r = ForeignCsv.rows(t, t.roles).rows;
      expect(r.length, 3);
      expect(r[0].kind, EntryKind.expense);
      expect(r[0].account, 'Карта');
      expect(r[0].category, 'Кафе');
      expect(r[0].amountMinor, 35000);
      expect(r[0].tags, ['кофе', 'утро']);
      expect(r[0].note, 'латте');
      expect(r[0].date, DateTime(2026, 11, 7, 12));
      expect(r[1].kind, EntryKind.income);
      expect(r[1].account, 'Карта');
      expect(r[1].category, 'Зарплата');
      expect(r[1].amountMinor, 5000000);
      expect(r[2].kind, EntryKind.transfer);
      expect(r[2].account, 'Карта');
      expect(r[2].toAccount, 'Наличные');
    });

    test('Money Manager: месяц первым, переводы один раз', () {
      final t = ForeignCsv.read(moneyManager);
      expect(t.format, 'Money Manager');
      final p = ForeignCsv.rows(t, t.roles);
      final r = p.rows;
      expect(r.length, 3);
      expect(r[0].date, DateTime(2026, 11, 7, 14, 30));
      expect(r[0].amountMinor, 1250);
      expect(r[0].subcategory, 'Lunch');
      expect(r[0].currency, 'USD');
      expect(r[1].date.day, 13);
      expect(r[1].amountMinor, 150000);
      expect(r[1].kind, EntryKind.income);
      expect(r[2].kind, EntryKind.transfer);
      expect(r[2].toAccount, 'Card');
      expect(p.skipped['Вторая половина перевода'], 1);
    });

    test('Monefy: знак суммы — тип', () {
      final t = ForeignCsv.read(monefy);
      expect(t.format, 'Monefy');
      final r = ForeignCsv.rows(t, t.roles).rows;
      expect(r[0].kind, EntryKind.expense);
      expect(r[0].amountMinor, 45000);
      expect(r[0].date, DateTime(2026, 11, 7, 12));
      expect(r[0].payee, 'Обед');
      expect(r[1].kind, EntryKind.income);
    });

    test('выписка Т-Банка в Windows-1251', () {
      final text = ForeignCsv.decode(cp1251Bytes(tbank));
      expect(text, tbank);
      final t = ForeignCsv.read(text);
      expect(t.format, 'Т-Банк (выписка)');
      final p = ForeignCsv.rows(t, t.roles);
      expect(p.skipped['Отменённые или отклонённые'], 1);
      final r = p.rows;
      expect(r.length, 3);
      expect(r[0].amountMinor, 123456);
      expect(r[0].kind, EntryKind.expense);
      expect(r[0].payee, 'Пятёрочка');
      expect(r[0].category, 'Супермаркеты');
      expect(r[0].account, '*1234');
      expect(r[0].date, DateTime(2026, 11, 7, 18, 22, 10));
      expect(r[1].kind, EntryKind.income);
      expect(r[1].account, '');
      // In dollars, but the card is in roubles: the rouble sum is taken.
      expect(r[2].amountMinor, 95000);
      expect(r[2].currency, isNull);
    });

    test('UTF-16 с BOM, табуляция и заголовок не в первой строке', () {
      const text =
          'Выписка по счёту\tИванов\n\nПериод: ноябрь\n'
          'Дата\tОписание\tСумма\n'
          '01.11.26\tАптека\t-399,90\n'
          '02.11.26\tКэшбэк\t+120\n';
      final bytes = [0xFF, 0xFE];
      for (final u in text.codeUnits) {
        bytes
          ..add(u & 0xFF)
          ..add(u >> 8);
      }
      final p = parseOf(ForeignCsv.decode(bytes));
      expect(p.rows.length, 2);
      expect(p.rows[0].payee, 'Аптека');
      expect(p.rows[0].amountMinor, 39990);
      expect(p.rows[0].date, DateTime(2026, 11, 1, 12));
      expect(p.rows[1].kind, EntryKind.income);
    });

    test('суммы без знака: решает человек', () {
      const text = 'Дата,Категория,Сумма\n2026-11-01,Кафе,300\n';
      final t = ForeignCsv.read(text);
      final p = ForeignCsv.rows(t, t.roles);
      expect(p.signed, isFalse);
      expect(p.rows.single.kind, EntryKind.expense);
      expect(
        ForeignCsv.rows(
          t,
          t.roles,
          unsignedAs: EntryKind.income,
        ).rows.single.kind,
        EntryKind.income,
      );
    });

    test('«Таблица операций» Finora', () async {
      sqfliteFfiInit();
      final temp = await Directory.systemTemp.createTemp('finora-v135-ops-');
      final repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/db',
      );
      await repo.save(
        base().copyWith(
          entries: [
            FinanceEntry(
              id: 'e1',
              kind: EntryKind.expense,
              amountMinor: 45990,
              currency: 'RUB',
              accountId: 'tink',
              categoryId: 'food',
              date: DateTime(2026, 11, 5, 9, 30),
              payee: 'Магнит',
              tags: const ['дом', 'еда'],
            ),
            FinanceEntry(
              id: 'e2',
              kind: EntryKind.transfer,
              amountMinor: 1000,
              currency: 'RUB',
              accountId: 'tink',
              toAccountId: 'cash',
              date: DateTime(2026, 11, 6),
            ),
          ],
        ),
      );
      final csv = await repo.exportCsv();
      await repo.close();
      await temp.delete(recursive: true);
      final t = ForeignCsv.read(csv);
      expect(t.format, 'Finora — операции');
      final rows = ForeignCsv.rows(t, t.roles).rows;
      expect(rows.length, 2);
      final r = [
        rows.firstWhere((x) => x.kind == EntryKind.expense),
        rows.firstWhere((x) => x.kind == EntryKind.transfer),
      ];
      expect(r[0].amountMinor, 45990);
      expect(r[0].payee, 'Магнит');
      expect(r[0].category, 'Продукты');
      expect(r[0].tags, ['дом', 'еда']);
      expect(r[0].date, DateTime(2026, 11, 5, 9, 30));
      expect(r[1].kind, EntryKind.transfer);
      expect(r[1].toAccount, 'Наличные');
    });

    test('полную копию Finora отправляет в «Из таблицы CSV»', () {
      expect(
        () => ForeignCsv.read('﻿"Finora CSV","1"\r\n"#accounts"\r\n'),
        throwsFormatException,
      );
    });

    test('без понятных заголовков — столбцы выбирает человек', () {
      final t = ForeignCsv.read('a;b;c\n01.11.2026;кофе;-200\n');
      expect(t.roles, everyElement(CsvRole.skip));
      expect(ForeignCsv.rows(t, t.roles).rows, isEmpty);
      final roles = [CsvRole.date, CsvRole.payee, CsvRole.amount];
      final r = ForeignCsv.rows(t, roles).rows.single;
      expect(r.amountMinor, 20000);
      expect(r.payee, 'кофе');
    });
  });

  test('суммы', () {
    final cases = {
      '1 234,56': 123456,
      '-1,234.56': -123456,
      '1 234,56 ₽': 123456,
      '−500': -50000,
      '(500)': -50000,
      '500-': -50000,
      '12.50': 1250,
      '12,5': 1250,
      '1,500': 150000,
      '12.500': 1250000,
      '1.234.567,8': 123456780,
      '\$ 9.99': 999,
      '0,005': 1,
      '': null,
      'abc': null,
    };
    for (final c in cases.entries) {
      expect(ForeignCsv.amount(c.key), c.value, reason: c.key);
    }
  });

  test('даты', () {
    expect(
      ForeignCsv.parseDate('2026-11-07T10:20:30'),
      DateTime(2026, 11, 7, 10, 20, 30),
    );
    expect(ForeignCsv.parseDate('07.11.2026'), DateTime(2026, 11, 7, 12));
    expect(ForeignCsv.parseDate('7-11-2026 9:05'), DateTime(2026, 11, 7, 9, 5));
    expect(ForeignCsv.parseDate('2026/11/07'), DateTime(2026, 11, 7, 12));
    expect(ForeignCsv.parseDate('7 ноября 2026'), DateTime(2026, 11, 7, 12));
    expect(ForeignCsv.parseDate('7 Nov 2026'), DateTime(2026, 11, 7, 12));
    expect(ForeignCsv.parseDate('31.02.2026'), isNull);
    expect(ForeignCsv.parseDate('вчера'), isNull);
    expect(ForeignCsv.currencyCode('руб.'), 'RUB');
    expect(ForeignCsv.currencyCode('RUR'), 'RUB');
    expect(ForeignCsv.currencyCode('\$'), 'USD');
    expect(ForeignCsv.currencyCode('xx'), isNull);
  });

  group('в базу', () {
    sqfliteFfiInit();
    late Directory temp;
    late FinanceRepository repository;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('finora-v135-');
      repository = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/db',
      );
      await repository.save(base());
    });
    tearDown(() async {
      await repository.close();
      await temp.delete(recursive: true);
    });

    test(
      'Дзен-мани добавляется к базе, счета и категории — по названию',
      () async {
        final (data, report) = ForeignCsv.apply(
          await repository.load(),
          parseOf(zen).rows,
          const ForeignOptions(),
          newId: id,
          iconFor: (_) => 5,
        );
        await repository.save(data); // the repository's validation passes
        final saved = await repository.load();
        expect(report.added, 4);
        expect(report.newAccounts, ['Доллары']);
        expect(
          saved.accounts.firstWhere((a) => a.name == 'Доллары').currency,
          'USD',
        );
        expect(report.newCategories, isEmpty);
        final expense = saved.entries.firstWhere(
          (e) => e.kind == EntryKind.expense,
        );
        expect(expense.accountId, 'tink');
        expect(expense.categoryId, 'food');
        final usd = saved.entries.firstWhere((e) => e.destinationMinor != null);
        expect(usd.amountMinor, 900000);
        expect(usd.destinationMinor, 10000);
        final same = saved.entries.firstWhere(
          (e) => e.kind == EntryKind.transfer && e.destinationMinor == null,
        );
        expect(same.toAccountId, 'cash');

        // The same file again: everything is a repeat.
        final (_, again) = ForeignCsv.apply(
          saved,
          parseOf(zen).rows,
          const ForeignOptions(),
          newId: id,
        );
        expect(again.added, 0);
        expect(again.duplicates, 4);
      },
    );

    test('новые категории, подкатегории и счета; или без создания', () async {
      final rows = parseOf(moneyManager).rows;
      final (data, report) = ForeignCsv.apply(
        await repository.load(),
        rows,
        const ForeignOptions(),
        newId: id,
        iconFor: (_) => 5,
      );
      await repository.save(data);
      expect(report.newAccounts, containsAll(['Cash', 'Card']));
      expect(report.newCategories, containsAll(['Food', 'Salary']));
      final food = data.categories.firstWhere((c) => c.name == 'Food');
      expect(food.subcategories, ['Lunch']);
      expect(food.icon, 5);

      final (plain, r2) = ForeignCsv.apply(
        base(),
        parseOf(monefy).rows,
        const ForeignOptions(createCategories: false),
        newId: id,
      );
      expect(r2.newCategories, isEmpty);
      final expense = plain.entries.firstWhere(
        (e) => e.kind == EntryKind.expense,
      );
      expect(expense.categoryId, 'other');
      final income = plain.entries.firstWhere(
        (e) => e.kind == EntryKind.income,
      );
      expect(income.categoryId, 'salary');
      await repository.save(plain);
    });

    test(
      'выписка: карта → выбранный счёт, без счёта → счёт по умолчанию',
      () async {
        final rows = ForeignCsv.rows(
          ForeignCsv.read(tbank),
          ForeignCsv.read(tbank).roles,
        ).rows;
        final (data, report) = ForeignCsv.apply(
          await repository.load(),
          rows,
          const ForeignOptions(
            accountMap: {'*1234': 'tink'},
            defaultAccountId: 'cash',
          ),
          newId: id,
        );
        await repository.save(data);
        expect(report.newAccounts, isEmpty);
        final added = data.entries;
        expect(added.where((e) => e.accountId == 'tink').length, 2);
        expect(
          added.where((e) => e.accountId == 'cash').single.kind,
          EntryKind.income,
        );
      },
    );
  });

  testWidgets('экран: столбцы, счета, «Добавить»', (tester) async {
    await initializeDateFormatting('ru');
    sqfliteFfiInit();
    late Directory temp;
    late FinanceRepository repository;
    late FinanceController controller;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('finora-v135-ui-');
      repository = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/db',
      );
      await repository.save(base());
      controller = FinanceController(
        repository,
        _Quiet(),
        await repository.load(),
      );
    });
    await tester.pumpWidget(
      FinanceScope(
        controller: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<int>(
                      builder: (_) => const ForeignImportScreen(
                        text: coinKeeper,
                        fileName: 'coinkeeper.csv',
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('CoinKeeper'), findsOneWidget);
    expect(
      find.text('Расходов: 1 · доходов: 1 · переводов: 1'),
      findsOneWidget,
    );
    expect(find.text('Создать «Карта»'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('foreign-import')));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(controller.data.entries.length, 3);
    expect(controller.data.accounts.map((a) => a.name), contains('Карта'));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      controller.dispose();
      await repository.close();
      await temp.delete(recursive: true);
    });
  });
}
