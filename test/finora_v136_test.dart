import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/app_version.dart';
import 'package:finora/domain/foreign_csv.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/payment_plan.dart';
import 'package:finora/domain/voice_command_parser.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/whats_new.dart';
import 'package:finora/presentation/widgets/amount_format.dart';
import 'package:finora/presentation/widgets/finora_orb.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

const g = amountGap;

FinanceData base({RecurringRule? rule}) => FinanceData(
  accounts: const [Account(id: 'a', name: 'Карта', openingMinor: 10000000)],
  categories: const [
    Category(id: 'loan', name: 'Кредиты', kind: EntryKind.expense),
  ],
  recurring: [?rule],
  members: const [Member(id: 'me', name: 'Я')],
  preferences: const AppPreferences(),
  demo: false,
);

RecurringRule loan({DateTime? next, int? total = 4600000}) => RecurringRule(
  id: 'l',
  name: 'Маркет',
  accountId: 'a',
  categoryId: 'loan',
  amountMinor: 385200,
  totalMinor: total,
  nextDate: next ?? DateTime(2026, 11, 16),
);

void main() {
  group('суммы с пробелами', () {
    test('группировка', () {
      expect(groupAmount('1250000'), '1${g}250${g}000');
      expect(groupAmount('1250000,5'), '1${g}250${g}000,5');
      expect(groupAmount('-12345.67'), '-12${g}345.67');
      expect(groupAmount('999'), '999');
      expect(groupAmount('1 2 3 4'), '1${g}234');
      expect(groupAmount(''), '');
    });

    test('курсор остаётся после той же цифры', () {
      const f = AmountGroupingFormatter();
      final v = f.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '12345',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(v.text, '12${g}345');
      expect(v.selection.baseOffset, 6);
      final mid = f.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '1234',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(mid.text, '1${g}234');
      expect(mid.selection.baseOffset, 3);
    });
  });

  test(
    'голос: «пятнадцатого числа», «до 15 числа», «двадцать пятое число»',
    () {
      for (final (phrase, day) in [
        ('обязательный платеж кредит пятнадцатого числа 12000', 15),
        ('обязательный платеж кредит 15 числа сумма 12000', 15),
        ('обязательный платеж кредит до 15 числа 12000', 15),
        ('обязательный платеж кредит 15-ого числа 12000', 15),
        ('обязательный платеж аренда двадцать пятое число 30000', 25),
        ('обязательный платеж ипотека первого числа на сумму 32000', 1),
      ]) {
        final c = VoiceCommandParser.parse([
          phrase,
        ], now: DateTime(2026, 11, 7));
        expect(c, isA<CreateRecurringCommand>(), reason: phrase);
        final r = c! as CreateRecurringCommand;
        expect(r.nextDate.day, day, reason: phrase);
        expect(r.name, isNot(contains('сумм')), reason: phrase);
        expect(r.name, isNot(contains('пятнадцат')), reason: phrase);
      }
    },
  );

  group('график платежей', () {
    test('осталось, «платёж N из M», последний меньше', () {
      final plan = PaymentPlan.of(loan(), const [], now: DateTime(2026, 11, 7));
      expect(plan.hasTotal, isTrue);
      expect(plan.leftMinor, 4600000);
      expect(plan.upcoming.length, 12);
      expect(plan.upcoming.first.number, 1);
      expect(plan.upcoming.first.of, 12);
      expect(plan.upcoming.last.amountMinor, 4600000 - 385200 * 11);
      expect(plan.upcoming[1].date, DateTime(2026, 12, 16));
      expect(plan.overdue, isFalse);
    });

    test('просрочен — красным', () {
      final plan = PaymentPlan.of(
        loan(next: DateTime(2026, 11, 1)),
        const [],
        now: DateTime(2026, 11, 7),
      );
      expect(plan.overdueDays, 6);
      expect(plan.upcoming.first.overdue, isTrue);
      expect(plan.upcoming[1].overdue, isFalse);
    });
  });

  group('оплата', () {
    sqfliteFfiInit();
    late Directory temp;
    late FinanceRepository repo;
    late FinanceController c;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('finora-v136-');
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/db',
      );
    });
    tearDown(() async {
      c.dispose();
      await repo.close();
      await temp.delete(recursive: true);
    });

    test('другая сумма подписки — запоминается', () async {
      await repo.save(base(rule: loan(total: null)));
      c = FinanceController(repo, _Quiet(), await repo.load());
      await c.confirmPayment('l', amountMinor: 399000, remember: true);
      final rule = c.data.recurring.single;
      expect(rule.amountMinor, 399000);
      expect(rule.nextDate, DateTime(2026, 12, 16));
      expect(c.data.entries.single.amountMinor, 399000);
      expect(c.ruleOf(c.data.entries.single)?.id, 'l');
      await c.confirmPayment('l', amountMinor: 100000);
      expect(c.data.recurring.single.amountMinor, 399000);
    });

    test('досрочно: полный платёж сдвигает дату, меньший — только остаток; '
        'всё погашено — платёж выключен', () async {
      await repo.save(base(rule: loan(total: 1000000)));
      c = FinanceController(repo, _Quiet(), await repo.load());
      await c.payEarly('l', amountMinor: 100000, now: DateTime(2026, 11, 7));
      var rule = c.data.recurring.single;
      expect(rule.nextDate, DateTime(2026, 11, 16));
      expect(PaymentPlan.of(rule, c.data.entries).leftMinor, 900000);
      expect(c.data.entries.single.note, 'Досрочно');
      await c.payEarly('l', amountMinor: 385200, now: DateTime(2026, 11, 8));
      rule = c.data.recurring.single;
      expect(rule.nextDate, DateTime(2026, 12, 16));
      await c.payEarly('l', amountMinor: 514800, now: DateTime(2026, 11, 9));
      rule = c.data.recurring.single;
      expect(PaymentPlan.of(rule, c.data.entries).done, isTrue);
      expect(rule.enabled, isFalse);
      // Kept in the base.
      final saved = (await repo.load()).recurring.single;
      expect(saved.totalMinor, 1000000);
    });
  });

  test('импорт: переводы между своими счетами — не траты', () {
    final rows = [
      ForeignRow(
        line: 1,
        date: DateTime(2026, 11, 5, 12),
        kind: EntryKind.expense,
        amountMinor: 500000,
        account: 'Т-Банк',
        payee: 'Перевод между своими счетами',
      ),
      ForeignRow(
        line: 2,
        date: DateTime(2026, 11, 5, 12),
        kind: EntryKind.income,
        amountMinor: 500000,
        account: 'Сбер',
        payee: 'Пополнение',
      ),
      ForeignRow(
        line: 3,
        date: DateTime(2026, 11, 6, 12),
        kind: EntryKind.expense,
        amountMinor: 300000,
        account: 'Т-Банк',
        payee: 'Перевод: Иван П.',
      ),
      ForeignRow(
        line: 4,
        date: DateTime(2026, 11, 6, 12),
        kind: EntryKind.expense,
        amountMinor: 20000,
        account: 'Т-Банк',
        category: 'Сбер',
      ),
      ForeignRow(
        line: 5,
        date: DateTime(2026, 11, 7, 12),
        kind: EntryKind.income,
        amountMinor: 70000,
        account: 'Т-Банк',
        note: 'С накопительного счета',
      ),
      ForeignRow(
        line: 6,
        date: DateTime(2026, 11, 7, 12),
        kind: EntryKind.expense,
        amountMinor: 70000,
        account: 'Т-Банк',
        category: 'Кредитная карта',
        payee: 'Магазин',
      ),
    ];
    final (out, merged) = ForeignCsv.ownTransfers(rows, {'Т-Банк', 'Сбер'});
    expect(merged, 3);
    expect(out.length, 5);
    expect(out[0].kind, EntryKind.transfer);
    expect(out[0].account, 'Т-Банк');
    expect(out[0].toAccount, 'Сбер');
    expect(out[1].kind, EntryKind.expense); // a person, not an account
    expect(out[2].kind, EntryKind.transfer);
    expect(out[2].toAccount, 'Сбер');
    expect(out[3].kind, EntryKind.transfer);
    expect(out[3].account, 'Свой счёт');
    expect(out[3].toAccount, 'Т-Банк');
    expect(out[4].kind, EntryKind.expense);
  });

  test('настройки 1.36 сохраняются; старая база — «Что нового»', () {
    const p = AppPreferences(
      paymentOrder: ['b', 'a'],
      avatar: 'emoji:🦊',
      seenVersion: '1.36.0',
      finoraThemed: false,
    );
    final back = AppPreferences.fromJson(p.toJson());
    expect(back.paymentOrder, ['b', 'a']);
    expect(back.avatar, 'emoji:🦊');
    expect(back.seenVersion, '1.36.0');
    expect(back.finoraThemed, isFalse);
    expect(AppPreferences.fromJson({}).seenVersion, 'old');
    expect(AppPreferences.fromJson({}).finoraThemed, isTrue);
    expect(
      AppPreferences.fromJson(const AppPreferences().toJson()).seenVersion,
      isNull,
    );
  });

  test('Финора в цвет темы', () {
    FinoraOrbPainter.theme = const Color(0xFFE53935);
    final red = HSLColor.fromColor(FinoraOrbPainter.mint).hue;
    expect(red, closeTo(HSLColor.fromColor(const Color(0xFFE53935)).hue, 2));
    FinoraOrbPainter.theme = FinoraOrbPainter.original;
    expect(
      HSLColor.fromColor(FinoraOrbPainter.mint).hue,
      closeTo(HSLColor.fromColor(FinoraOrbPainter.original).hue, 2),
    );
  });

  testWidgets('«Что нового» показывается один раз после обновления', (
    tester,
  ) async {
    sqfliteFfiInit();
    late Directory temp;
    late FinanceRepository repo;
    late FinanceController c;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('finora-v136-new-');
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/db',
      );
      await repo.save(
        base().copyWith(preferences: const AppPreferences(seenVersion: 'old')),
      );
      c = FinanceController(repo, _Quiet(), await repo.load());
    });
    late BuildContext ctx;
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    final shown = WhatsNew.check(ctx);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('whats-new')), findsOneWidget);
    expect(find.text('Что нового в $appVersion'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('whats-new-ok')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(await tester.runAsync(() => shown), isTrue);
    expect(c.data.preferences.seenVersion, appVersion);
    expect(await tester.runAsync(() => WhatsNew.check(ctx)), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      c.dispose();
      await repo.close();
      await temp.delete(recursive: true);
    });
  });
}
