import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/entry_editor.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const ocr = MethodChannel('finora/ocr');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const shares = MethodChannel('finora/receipt_share');
  late Directory dir;
  late FinanceRepository repo;
  late FinanceController controller;
  late String source;
  late String text;
  late int ocrCalls;
  Completer<Object?>? pending;
  String? shared;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAFUlEQVR4nGMUCVj1nwEJMDGgAcICAIYaAhXIS0xyAAAAAElFTkSuQmCC',
  );
  setUp(() async {
    await initializeDateFormatting('ru');
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('finance-import-ui-');
    source = '${dir.path}/source.png';
    await File(source).writeAsBytes(png);
    await Directory('${dir.path}/cache').create();
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/ledger',
    );
    await repo.save(
      const FinanceData(
        accounts: [
          Account(id: 'card', name: 'Карта', openingMinor: 1000000),
          Account(id: 'cash', name: 'Наличные'),
        ],
        categories: [
          Category(id: 'food', name: 'Продукты', kind: EntryKind.expense),
          Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
        ],
        members: [Member(id: 'me', name: 'Я')],
        demo: false,
      ),
    );
    controller = FinanceController(repo, _Quiet(), await repo.load());
    text =
        'ПЯТЁРОЧКА\nКАССОВЫЙ ЧЕК\n05.11.2026 14:32\nИТОГО 244,80 ₽\nНДС 22,25\nНАЛИЧНЫМИ 500,00\nСДАЧА 255,20';
    ocrCalls = 0;
    pending = null;
    shared = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      paths,
      (call) async => call.method == 'getApplicationSupportDirectory'
          ? dir.path
          : '${dir.path}/cache',
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(shares, (
      call,
    ) async {
      final result = shared;
      shared = null;
      return result;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(ocr, (call) async {
      if (call.method == 'recognize') {
        ocrCalls++;
        expect(
          (call.arguments as Map)['path'],
          startsWith('${dir.path}/receipts/scan-'),
        );
        return pending == null
            ? {'text': text, 'confidence': .93}
            : pending!.future;
      }
      if (call.method == 'cancel') {
        if (pending != null && !pending!.isCompleted) {
          pending!.completeError(PlatformException(code: 'OCR_CANCELLED'));
        }
        return null;
      }
      throw MissingPluginException();
    });
  });
  tearDown(() async {
    controller.dispose();
    await repo.close();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(ocr, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(paths, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(shares, null);
    await dir.delete(recursive: true);
  });
  Future<void> flush(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue);
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    await mount(tester);
    showEntryEditor(
      tester.element(find.byType(HomeShell)),
      scanImagePath: source,
    );
    await flush(
      tester,
      () => find.byKey(const ValueKey('scan-review')).evaluate().isNotEmpty,
    );
  }

  Future<void> reveal(
    WidgetTester tester,
    Finder item, {
    bool up = false,
  }) async {
    await tester.scrollUntilVisible(
      item,
      up ? -220 : 220,
      scrollable: find
          .descendant(
            of: find.byType(EntryEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'OCR fills a draft, only explicit save writes expense and persists private receipt',
    (tester) async {
      await open(tester);
      expect(ocrCalls, 1);
      expect(controller.data.entries, isEmpty);
      expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .any((f) => f.controller?.text == '244.80'),
        isTrue,
      );
      await reveal(tester, find.text('Продукты'));
      expect(
        tester
            .widget<ChoiceChip>(
              find.ancestor(
                of: find.text('Продукты'),
                matching: find.byType(ChoiceChip),
              ),
            )
            .selected,
        isTrue,
      );
      await reveal(tester, find.text('Сохранить операцию'));
      await tester.tap(find.text('Сохранить операцию'));
      await flush(tester, () => controller.data.entries.length == 1);
      final e = controller.data.entries.single;
      expect(e.amountMinor, 24480);
      expect(e.categoryId, 'food');
      expect(e.payee, 'ПЯТЁРОЧКА');
      expect(e.kind, EntryKind.expense);
      expect(
        FinanceEngine.balance(
          controller.data.accounts.first,
          controller.data.entries,
        ),
        975520,
      );
      expect(controller.data.preferences.lastExpenseCategoryId, 'food');
      expect(
        await tester.runAsync(() => File(e.attachmentPath!).readAsBytes()),
        png,
      );
      expect(await tester.runAsync(() => File(source).exists()), isTrue);
      final restored = await tester.runAsync(repo.load);
      expect(restored!.entries.single.amountMinor, 24480);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'ambiguous bank transfer needs explicit type and category, cannot silently become expense',
    (tester) async {
      text = 'Перевод исполнен\nКому: Анна\nСумма перевода 500 ₽';
      await open(tester);
      expect(find.text('Выберите тип операции ниже.'), findsOneWidget);
      await reveal(tester, find.text('Сохранить операцию'));
      await tester.tap(find.text('Сохранить операцию'));
      await tester.pumpAndSettle();
      expect(controller.data.entries, isEmpty);
      expect(find.text('Выберите тип распознанной операции.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await reveal(tester, find.byType(SegmentedButton<EntryKind>), up: true);
      await tester.tap(find.text('Расход').first);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Продукты'));
      await tester.tap(find.text('Продукты'));
      await reveal(tester, find.text('Сохранить операцию'));
      await tester.tap(find.text('Сохранить операцию'));
      await flush(tester, () => controller.data.entries.isNotEmpty);
      expect(controller.data.entries.single.kind, EntryKind.expense);
    },
  );
  testWidgets('foreign currency is not silently posted to a RUB account', (
    tester,
  ) async {
    text = 'Purchase\nMerchant: SPAR\nAmount 12.50 USD\n05.11.2026';
    await open(tester);
    await reveal(tester, find.text('Продукты'));
    await tester.tap(find.text('Продукты'));
    await reveal(tester, find.text('Сохранить операцию'));
    await tester.tap(find.text('Сохранить операцию'));
    await tester.pumpAndSettle();
    expect(controller.data.entries, isEmpty);
    expect(find.textContaining('На изображении USD.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await reveal(tester, find.text('Исправить валюту на RUB'), up: true);
    await tester.tap(find.text('Исправить валюту на RUB'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Сохранить операцию'));
    await tester.tap(find.text('Сохранить операцию'));
    await flush(tester, () => controller.data.entries.isNotEmpty);
    expect(controller.data.entries.single.currency, 'RUB');
    expect(controller.data.entries.single.amountMinor, 1250);
  });
  testWidgets(
    'cancelled OCR returns to intact form without a financial write',
    (tester) async {
      pending = Completer<Object?>();
      await mount(tester);
      showEntryEditor(
        tester.element(find.byType(HomeShell)),
        scanImagePath: source,
      );
      for (var i = 0; i < 100 && ocrCalls == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ocrCalls, 1);
      await tester.tap(find.byKey(const ValueKey('cancel-receipt-scan')));
      await flush(
        tester,
        () => find.byKey(const ValueKey('scan-receipt')).evaluate().isNotEmpty,
      );
      expect(find.byKey(const ValueKey('scan-review')), findsNothing);
      expect(controller.data.entries, isEmpty);
      expect(await tester.runAsync(() => File(source).exists()), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'recognition review remains usable on small and landscape screens with large text',
    (tester) async {
      await open(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final size in [const Size(320, 640), const Size(640, 360)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await reveal(tester, find.text('Сохранить операцию'));
        expect(find.text('Сохранить операцию').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(controller.data.entries, isEmpty);
    },
  );
  testWidgets(
    'coldstart share opens one recognition draft and creates no automatic operation',
    (tester) async {
      shared = source;
      await mount(tester);
      await flush(
        tester,
        () => find.byKey(const ValueKey('scan-review')).evaluate().isNotEmpty,
      );
      expect(ocrCalls, 1);
      expect(find.byType(EntryEditor), findsOneWidget);
      expect(controller.data.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
