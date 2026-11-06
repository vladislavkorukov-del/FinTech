import 'dart:convert';
import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/account_import_screen.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Finance 1.21: accounts from a screenshot of another finance app are
/// reviewed and added with their balances; the screenshot is not kept.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const ocr = MethodChannel('finora/ocr');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory dir;
  late FinanceRepository repository;
  late FinanceController controller;
  late String source;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAFUlEQVR4nGMUCVj1nwEJMDGgAcICAIYaAhXIS0xyAAAAAElFTkSuQmCC',
  );
  setUp(() async {
    await initializeDateFormatting('ru');
    dir = await Directory.systemTemp.createTemp('finora-v121-import-');
    source = '${dir.path}/shot.png';
    await File(source).writeAsBytes(png);
    await Directory('${dir.path}/cache').create();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      paths,
      (call) async => call.method == 'getApplicationSupportDirectory'
          ? dir.path
          : '${dir.path}/cache',
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(ocr, (call) async {
      if (call.method == 'recognize') {
        return {
          'text':
              'Счета\nВсего 1 318 300 ₽\nНаличные 12 500 ₽\n'
              'Тинькофф Black •• 4821   45 300,50 ₽\nКопилка 7 000 ₽\n'
              'Кредитка  −30 000 ₽',
          'confidence': .93,
        };
      }
      return null;
    });
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/db',
    );
    await repository.save(
      const FinanceData(
        accounts: [Account(id: 'old', name: 'Наличные', openingMinor: 500)],
        members: [Member(id: 'me', name: 'Я')],
        demo: false,
      ),
    );
    controller = FinanceController(
      repository,
      _Quiet(),
      await repository.load(),
    );
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(ocr, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(paths, null);
    controller.dispose();
    await repository.close();
    await dir.delete(recursive: true);
  });

  Future<void> flush(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 80 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (done()) await tester.pumpAndSettle();
  }

  testWidgets('review, edit and add the accounts', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.app(Brightness.dark, 'midnight'),
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AccountImportScreen(initialPath: source),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await flush(
      tester,
      () =>
          find
              .byKey(const ValueKey('account-import-add'))
              .evaluate()
              .isNotEmpty &&
          tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('account-import-add')),
                  )
                  .onPressed !=
              null,
    );
    // ignore: avoid_print
    print(
      'TEXTS: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList()}',
    );
    // Four accounts; the one that already exists is unticked.
    expect(find.byKey(const ValueKey('account-import-name-3')), findsOneWidget);
    expect(find.text('Такой счёт уже есть'), findsOneWidget);
    expect(find.text('Добавить счетов: 3'), findsOneWidget);
    // Rename one before adding.
    await tester.enterText(
      find.byKey(const ValueKey('account-import-name-2')),
      'Копилка на отпуск',
    );
    await tester.tap(find.byKey(const ValueKey('account-import-add')));
    await flush(tester, () => controller.data.accounts.length == 4);
    final added = {for (final a in controller.data.accounts) a.name: a};
    expect(
      added.keys,
      containsAll(['Тинькофф Black', 'Копилка на отпуск', 'Кредитка']),
    );
    expect(added['Тинькофф Black']!.openingMinor, 4530050);
    expect(added['Тинькофф Black']!.lastFour, '4821');
    expect(added['Тинькофф Black']!.bank, 'Т-Банк');
    expect(added['Тинькофф Black']!.type, 'debit');
    expect(added['Копилка на отпуск']!.type, 'savings');
    expect(added['Кредитка']!.openingMinor, -3000000);
    expect(added['Кредитка']!.type, 'credit');
    // The existing «Наличные» was not duplicated.
    expect(
      controller.data.accounts.where((a) => a.name == 'Наличные'),
      hasLength(1),
    );
    // The copied screenshot is not kept.
    final receipts = Directory('${dir.path}/receipts');
    expect(receipts.existsSync() ? receipts.listSync() : const [], isEmpty);
    expect(tester.takeException(), isNull);
  });
}
