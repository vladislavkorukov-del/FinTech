import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
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

/// Finance 1.19/1.20: the voice orb in the bottom bar opens the editor, listens and
/// fills it; the person saves.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const voice = MethodChannel('finora/voice');
  late Directory dir;
  late FinanceRepository repository;
  late FinanceController controller;
  late List<String> heard;
  var calls = 0;
  setUp(() async {
    await initializeDateFormatting('ru');
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('finora-v119-voice-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/db',
    );
    await repository.save(
      FinanceData(
        accounts: const [Account(id: 'card', name: 'Карта')],
        categories: createDemoData(DateTime(2026, 11, 6)).categories,
        members: const [Member(id: 'me', name: 'Я')],
        demo: false,
      ),
    );
    controller = FinanceController(
      repository,
      _Quiet(),
      await repository.load(),
    );
    heard = ['пятерочка 450 рублей', 'пятерочка 450'];
    calls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(voice, (
      call,
    ) async {
      if (call.method == 'listen') {
        calls++;
        return heard;
      }
      return true;
    });
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(voice, null);
    controller.dispose();
    await repository.close();
    await dir.delete(recursive: true);
  });

  Finder field(String value) => find.byWidgetPredicate(
    (w) => w is EditableText && w.controller.text == value,
  );

  Future<void> flush(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 60 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openByVoice(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-voice')));
    await flush(
      tester,
      () => find.byKey(const ValueKey('voice-heard')).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('microphone fills the editor; saving needs a tap', (
    tester,
  ) async {
    await openByVoice(tester);
    expect(calls, 1);
    expect(find.byType(EntryEditor), findsOneWidget);
    expect(
      find.textContaining('Услышал: «пятерочка 450 рублей»'),
      findsOneWidget,
    );
    expect(field('450.00'), findsOneWidget);
    expect(find.text('Продукты'), findsWidgets);
    // Nothing is saved by voice alone.
    expect(controller.data.entries, isEmpty);
    final save = find.text('Сохранить операцию');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find
          .descendant(
            of: find.byType(EntryEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await flush(tester, () => controller.data.entries.isNotEmpty);
    final entry = controller.data.entries.single;
    expect(entry.amountMinor, 45000);
    expect(entry.kind, EntryKind.expense);
    expect(entry.payee, 'Пятёрочка');
    expect(entry.serviceId, 'store_pyaterochka');
    expect(
      controller.data.categories
          .firstWhere((c) => c.id == entry.categoryId)
          .name,
      'Продукты',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled speech opens nothing; the editor still listens', (
    tester,
  ) async {
    heard = [];
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-voice')));
    await flush(tester, () => calls > 0);
    await tester.pumpAndSettle();
    // 1.23: the orb listens before opening anything.
    expect(find.byType(EntryEditor), findsNothing);
    expect(controller.data.entries, isEmpty);
    // A long press adds by hand; the editor's own button listens again.
    await tester.longPress(find.byKey(const ValueKey('nav-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Поступление на счёт'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryEditor), findsOneWidget);
    heard = ['зарплата 90 тысяч'];
    await tester.tap(find.byKey(const ValueKey('voice-entry')));
    await flush(
      tester,
      () => find.byKey(const ValueKey('voice-heard')).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(field('90000.00'), findsOneWidget);
    expect(find.text('Зарплата'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
