import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/data/finora_csv.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/management.dart';
import 'package:finora/presentation/whats_new.dart';
import 'package:finora/presentation/widgets/finora_orb.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

const base = FinanceData(
  accounts: [Account(id: 'a', name: 'Карта')],
  categories: [Category(id: 'food', name: 'Продукты', kind: EntryKind.expense)],
  members: [Member(id: 'me', name: 'Я')],
  demo: false,
);

void main() {
  test('строка списка: название, количество, цена', () {
    var s = ShoppingScreen.parse('1', 'молоко 2 шт 89');
    expect((s.name, s.quantity, s.priceMinor), ('молоко', '2 шт', 8900));
    s = ShoppingScreen.parse('1', 'хлеб');
    expect((s.name, s.quantity, s.priceMinor), ('хлеб', '', null));
    s = ShoppingScreen.parse('1', 'Сыр 1 кг 1 250,50 руб');
    expect((s.name, s.quantity, s.priceMinor), ('Сыр', '1 кг', 125050));
    s = ShoppingScreen.parse('1', 'яйца 10 шт');
    expect((s.name, s.quantity, s.priceMinor), ('яйца', '10 шт', null));
  });

  test('список хранится в базе, в JSON и в CSV', () async {
    sqfliteFfiInit();
    final temp = await Directory.systemTemp.createTemp('finora-v138-');
    final repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/db',
    );
    const list = [
      ShoppingItem(
        id: 's1',
        name: 'Молоко',
        quantity: '2 шт',
        priceMinor: 8900,
      ),
      ShoppingItem(id: 's2', name: 'Хлеб', done: true),
    ];
    await repo.save(base.copyWith(shopping: list));
    final loaded = await repo.load();
    expect(loaded.shopping.map((s) => s.toJson()), list.map((s) => s.toJson()));
    final csv = await repo.exportFullCsv();
    expect(csv, contains('"#shopping"'));
    await repo.save(base);
    await repo.importCsv(csv);
    expect((await repo.load()).shopping.length, 2);
    final json = await repo.exportJson();
    await repo.save(base);
    await repo.importJson(json);
    expect((await repo.load()).shopping.first.priceMinor, 8900);
    // A CSV from 1.37 has no shopping table.
    final old = FinoraCsv.decode(
      csv.split('"#shopping"').first,
      schema: FinanceRepository.schemaVersion,
    );
    expect((old['data']! as Map)['shopping'], isEmpty);
    await repo.close();
    await temp.delete(recursive: true);
  });

  testWidgets('экран: добавить, отметить, убрать купленное', (tester) async {
    sqfliteFfiInit();
    late Directory temp;
    late FinanceRepository repo;
    late FinanceController c;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('finora-v138-ui-');
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/db',
      );
      await repo.save(base);
      c = FinanceController(repo, _Quiet(), await repo.load());
    });
    Future<void> settle([bool Function()? completed]) async {
      for (
        var i = 0;
        i < (completed == null ? 10 : 150) &&
            (completed == null || !completed());
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: const MaterialApp(home: ShoppingScreen()),
      ),
    );
    expect(find.text('Список пуст'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('shopping-input')),
      'молоко 2 шт 89',
    );
    await tester.tap(find.byKey(const ValueKey('shopping-add')));
    await settle();
    await tester.enterText(
      find.byKey(const ValueKey('shopping-input')),
      'хлеб',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle();
    expect(c.data.shopping.map((s) => s.name), ['молоко', 'хлеб']);
    expect(find.byKey(const ValueKey('shopping-planned')), findsOneWidget);
    final milk = c.data.shopping.first.id;
    await tester.tap(find.byKey(ValueKey('shopping-check-$milk')));
    await settle();
    expect(c.data.shopping.first.done, isTrue);
    expect(find.byKey(const ValueKey('shopping-record')), findsOneWidget);
    expect(find.textContaining('89'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('shopping-clear-done')));
    // SQLite completion is observed, rather than assuming a fixed200ms under load.
    await settle(() => c.data.shopping.length == 1);
    expect(c.data.shopping.map((s) => s.name), ['хлеб']);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      c.dispose();
      await repo.close();
      await temp.delete(recursive: true);
    });
  });

  testWidgets('Финора в окне — своего размера, не на всю ширину', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AlertDialog(
            icon: FinoraCharacter(size: 64, moods: [FinoraMood.thinking]),
            title: Text('Оплатить «Интернет» досрочно?'),
            content: Text('Расход запишется сегодня.'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final paint = tester.getSize(
      find
          .descendant(
            of: find.byType(FinoraCharacter),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    expect(paint.width, 64);
    expect(paint.height, 64);
    final title = tester.getRect(find.text('Оплатить «Интернет» досрочно?'));
    final orb = tester.getRect(find.byType(FinoraCharacter));
    expect(orb.bottom, lessThanOrEqualTo(title.top + 1));
    await tester.pumpWidget(const SizedBox());
  });

  test('«Что нового» в 1.38', () {
    expect(WhatsNew.items.map((i) => i.$2), contains('Список покупок'));
  });
}
