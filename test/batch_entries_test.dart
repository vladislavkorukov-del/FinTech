import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/batch_entries.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/batch_entries_screen.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// «Несколько операций»: a list read line by line, all saved at once.
void main() {
  const categories = [
    Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
    Category(id: 'taxi', name: 'Транспорт', kind: EntryKind.expense),
    Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
  ];

  test('a pasted list becomes rows', () {
    final rows = BatchEntries.parse(
      'кб 500\n• такси 350\nобед 450+120\nзарплата +90 000\n\nхлеб',
      categories: categories,
      resolvePayee: (p) => p.toLowerCase() == 'кб' ? 'Красное&Белое' : p,
    );
    expect(rows, hasLength(5));
    expect(rows[0].payee, 'Красное&Белое');
    expect(rows[0].amountMinor, 50000);
    expect(rows[0].kind, EntryKind.expense);
    expect(rows[1].amountMinor, 35000);
    expect(rows[2].amountMinor, 57000);
    expect(rows[3].kind, EntryKind.income);
    expect(rows[3].amountMinor, 9000000);
    expect(rows[3].categoryId, anyOf(isNull, 'salary'));
    // A line without a sum is kept for the person to finish.
    expect(rows[4].amountMinor, isNull);
    expect(rows[4].ready, isFalse);
  });

  testWidgets('rows are saved together on one account', (tester) async {
    sqfliteFfiInit();
    await initializeDateFormatting('ru');
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('finora-batch-'),
    );
    final repo = (await tester.runAsync(
      () => FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir!.path}/a.db',
      ),
    ))!;
    final demo = createDemoData(DateTime.now());
    await tester.runAsync(() => repo.save(demo.copyWith(demo: false)));
    final data = await tester.runAsync(repo.load);
    final c = FinanceController(repo, _Quiet(), data!);
    final before = c.data.entries.length;
    final old = {for (final e in c.data.entries) e.id};
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.app(Brightness.light, 'tropic'),
          home: const BatchEntriesScreen(initialText: 'хлеб 80\nтакси 350'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('batch-payee-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('batch-add-row')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('batch-payee-2')), 'Обед');
    await tester.enterText(
      find.byKey(const ValueKey('batch-amount-2')),
      '200+100',
    );
    await tester.pump();
    expect(find.textContaining('Сохранить 3'), findsOneWidget);
    // «Обед» has no category yet: the row asks for one.
    await tester.tap(find.byKey(const ValueKey('batch-save')));
    await tester.pump();
    expect(c.data.entries.length, before);
    expect(find.text('Выберите категорию'), findsWidgets);
    for (var i = 0; i < 3; i++) {
      final empty = find.byKey(ValueKey('batch-category-$i-null'));
      if (empty.evaluate().isEmpty) continue;
      await tester.tap(empty);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продукты').last);
      await tester.pumpAndSettle();
    }
    expect(find.text('Выберите категорию'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('batch-save')));
    for (var i = 0; i < 100 && c.data.entries.length == before; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    final added = c.data.entries.where((e) => !old.contains(e.id)).toList()
      ..sort((a, b) => a.amountMinor.compareTo(b.amountMinor));
    expect(added, hasLength(3));
    expect(added.map((e) => e.amountMinor), [8000, 30000, 35000]);
    expect(added.map((e) => e.accountId).toSet(), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.runAsync(repo.close);
  });
}
