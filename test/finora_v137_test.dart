import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/i18n.dart';
import 'package:finora/presentation/l10n_table.dart';
import 'package:finora/presentation/l10n_widgets.dart' as l10n;
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

void main() {
  tearDown(() => AppLanguage.code = 'ru');

  group('сколько откладывать', () {
    final goal = Goal(
      id: 'g',
      name: 'Отпуск',
      targetMinor: 15000000,
      deadline: DateTime(2027, 5, 7),
    );
    test('в день, неделю и месяц до срока', () {
      final pace = FinanceEngine.savingsPace(
        goal,
        3000000,
        now: DateTime(2026, 11, 7),
      )!;
      expect(pace.days, 181);
      expect(pace.left, 12000000);
      // 120 000 ₽ / 181 day ≈ 663 ₽ a day, rounded up to whole roubles.
      expect(pace.day, 66300);
      expect(pace.week, greaterThanOrEqualTo(pace.day * 7 - 100));
      expect(pace.month, greaterThan(pace.week * 4));
      expect(pace.month * 6, greaterThanOrEqualTo(12000000));
    });
    test('без срока, накоплено или срок прошёл', () {
      expect(
        FinanceEngine.savingsPace(
          const Goal(id: 'x', name: 'x', targetMinor: 100),
          0,
        ),
        isNull,
      );
      expect(FinanceEngine.savingsPace(goal, 15000000), isNull);
      final late = FinanceEngine.savingsPace(
        goal,
        0,
        now: DateTime(2027, 6, 1),
      )!;
      expect(late.days, lessThanOrEqualTo(0));
      expect(late.left, 15000000);
    });
  });

  group('языки', () {
    test('девять языков, у каждой строки все переводы и подстановки', () {
      expect(AppLanguage.names.keys, [
        'ru', 'en', 'es', 'pt', 'fr', 'de', 'zh', 'hi', 'ar', //
      ]);
      expect(l10nTable.length, greaterThan(900));
      final hole = RegExp(r'\{\d\}');
      for (final e in l10nTable.entries) {
        expect(e.value.length, l10nLanguages.length, reason: e.key);
        final need = hole.allMatches(e.key).map((m) => m[0]).toSet();
        for (final v in e.value) {
          expect(v.trim(), isNotEmpty, reason: e.key);
          expect(
            hole.allMatches(v).map((m) => m[0]).toSet(),
            need,
            reason: '${e.key} → $v',
          );
        }
      }
    });

    test('точные строки, строки со значениями и названия внутри', () {
      AppLanguage.code = 'en';
      expect(tr('Главная'), 'Home');
      expect(tr('Осталось 5 000 ₽'), 'Left 5 000 ₽');
      expect(tr('платёж 7 из 12'), 'payment 7 of 12');
      expect(
        tr('Основная карта → Накопительный · 6 нояб.'),
        'Main card → Savings · 6 нояб.',
      );
      expect(tr('Kaspi'), 'Kaspi');
      AppLanguage.code = 'es';
      expect(tr('Главная'), 'Inicio');
      expect(tr('Удалить «Netflix»?'), '¿Borrar «Netflix»?');
      AppLanguage.code = 'ar';
      expect(AppLanguage.rtl, isTrue);
      expect(tr('Настройки'), 'الإعدادات');
      AppLanguage.code = 'ru';
      expect(tr('Главная'), 'Главная');
    });

    testWidgets('Text и подписи полей переводятся сами', (tester) async {
      AppLanguage.code = 'de';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                l10n.Text('Настройки'),
                TextField(
                  decoration: l10n.InputDecoration(
                    labelText: 'Название',
                    hintText: 'Например: 150 000',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Einstellungen'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Z. B.: 150 000'), findsOneWidget);
      AppLanguage.code = 'ru';
    });

    testWidgets('на английском главные экраны без русских строк', (
      tester,
    ) async {
      await initializeDateFormatting();
      sqfliteFfiInit();
      late FinanceController c;
      late FinanceRepository repo;
      late Directory temp;
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('finora-v137-');
        repo = await FinanceRepository.open(
          factory: databaseFactoryFfi,
          path: '${temp.path}/db',
        );
        final demo = createDemoData(DateTime.now());
        await repo.save(
          demo.copyWith(
            preferences: demo.preferences.copyWith(
              language: 'en',
              onboarded: true,
            ),
          ),
        );
        c = FinanceController(repo, _Quiet(), await repo.load());
      });
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        FinoraApp(controller: c, requireDeviceSecurity: false),
      );
      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      // Store names are names, not words.
      const names = {'ВкусВилл', 'Пятёрочка', 'Магнит'};
      final left = <String>{};
      void collect() {
        for (final e in find.byType(RichText).evaluate()) {
          final t = (e.widget as RichText).text.toPlainText();
          if (RegExp('[А-Яа-яЁё]').hasMatch(t) && !names.any(t.contains)) {
            left.add(t);
          }
        }
      }

      await settle();
      collect();
      for (final tab in ['Transactions', 'Analytics', 'More']) {
        await tester.tap(find.text(tab).last);
        await settle();
        collect();
      }
      for (final item in ['Accounts', 'Dreams', 'Payments & subscriptions']) {
        await tester.tap(find.text(item).first);
        await settle();
        collect();
        await tester.pageBack();
        await settle();
      }
      expect(left, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        c.dispose();
        await repo.close();
        await temp.delete(recursive: true);
      });
      AppLanguage.code = 'ru';
    });
  });

  test('светлая тема заметно окрашена цветом темы', () {
    for (final accent in ['emerald', 'aurora', 'tropic']) {
      final light = AppTheme.app(Brightness.light, accent);
      final bg = HSLColor.fromColor(light.colorScheme.surfaceContainerLowest);
      expect(bg.lightness, greaterThan(.8), reason: accent);
      expect(bg.saturation, greaterThan(.12), reason: accent);
    }
  });
}
