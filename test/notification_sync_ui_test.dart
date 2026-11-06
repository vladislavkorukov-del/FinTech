import 'dart:async';
import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/management.dart';
import 'package:finora/presentation/screens/settings.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _GatedNotifications extends NotificationService {
  final snapshots = <FinanceData>[];
  final gates = <Completer<void>>[];
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> sync(FinanceData data) {
    snapshots.add(data);
    final gate = Completer<void>();
    gates.add(gate);
    return gate.future;
  }

  void succeed(int index) => gates[index].complete();
  void fail(int index) =>
      gates[index].completeError(StateError('native scheduler unavailable'));
  void releaseAll() {
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late FinanceRepository repository;
  late FinanceController controller;
  late _GatedNotifications notifications;

  setUp(() async {
    await initializeDateFormatting('ru');
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('finance-sync-ui-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/ledger.db',
    );
    await repository.save(
      const FinanceData(
        accounts: [Account(id: 'card', name: 'Карта', openingMinor: 1000000)],
        categories: [
          Category(
            id: 'subscriptions',
            name: 'Подписки',
            kind: EntryKind.expense,
          ),
        ],
        members: [Member(id: 'me', name: 'Я')],
      ),
    );
    notifications = _GatedNotifications();
    controller = FinanceController(
      repository,
      notifications,
      await repository.load(),
    );
  });
  tearDown(() async {
    controller.dispose();
    notifications.releaseAll();
    await repository.close();
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(430, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FinanceScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, 'coffee'),
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(ready(), isTrue);
    await tester.pump();
  }

  Future<void> reveal(
    WidgetTester tester,
    Finder target, {
    bool sheet = false,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final scrollable = sheet
        ? find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable),
              )
              .first
        : find.byType(Scrollable).first;
    await tester.scrollUntilVisible(target, 180, scrollable: scrollable);
    await tester.pumpAndSettle();
  }

  Finder toggle() =>
      find.widgetWithText(SwitchListTile, 'Финансовые напоминания');
  RecurringRule rule() => RecurringRule(
    id: 'rent',
    name: 'Аренда',
    accountId: 'card',
    categoryId: 'subscriptions',
    amountMinor: 10000,
    nextDate: DateTime.now().add(const Duration(days: 10)),
    reminderEnabled: true,
    paymentType: 'mandatory',
  );

  test(
    'ordinary financial commit does not await notification scheduling or roll back on failure',
    () async {
      final account = controller.data.accounts.single.copyWith(
        name: 'Основная',
      );
      await controller.saveAccount(account);
      expect(controller.data.accounts.single.name, 'Основная');
      expect((await repository.load()).accounts.single.name, 'Основная');
      expect(controller.notificationSyncPending, isTrue);
      expect(notifications.gates, hasLength(1));
      notifications.fail(0);
      final result = await controller.waitForNotificationSync();
      expect(result.succeeded, isFalse);
      expect(controller.notificationSyncResult?.succeeded, isFalse);
      expect(controller.notificationSyncPending, isFalse);
      expect((await repository.load()).accounts.single.name, 'Основная');
    },
  );

  test(
    'older sync completion cannot replace the status of a newer queued update',
    () async {
      await controller.saveAccount(
        controller.data.accounts.single.copyWith(name: 'Первое'),
      );
      final older = controller.waitForNotificationSync();
      await controller.saveAccount(
        controller.data.accounts.single.copyWith(name: 'Второе'),
      );
      final newer = controller.waitForNotificationSync();
      expect(notifications.snapshots, hasLength(2));
      notifications.fail(0);
      expect((await older).succeeded, isFalse);
      expect(controller.notificationSyncPending, isTrue);
      expect(controller.notificationSyncResult, isNull);
      notifications.succeed(1);
      expect((await newer).succeeded, isTrue);
      expect(controller.notificationSyncResult?.succeeded, isTrue);
      expect(controller.data.accounts.single.name, 'Второе');
    },
  );

  testWidgets(
    'global opt-in remains busy until the already queued sync completes',
    (tester) async {
      await mount(tester, const SettingsScreen(section: 'notifications'));
      await reveal(tester, toggle());
      await tester.tap(toggle());
      await until(tester, () => notifications.gates.length == 1);
      expect(controller.data.preferences.notifications, isTrue);
      expect(notifications.permissionRequests, 1);
      expect(controller.notificationSyncPending, isTrue);
      expect(find.text('Обновляем уведомления…'), findsOneWidget);
      final retry = tester.widget<TextButton>(
        find.byKey(const ValueKey('notification-sync-retry')),
      );
      expect(retry.onPressed, isNull);
      expect(notifications.snapshots, hasLength(1));
      notifications.succeed(0);
      await until(tester, () => !controller.notificationSyncPending);
      await tester.pumpAndSettle();
      expect(notifications.snapshots, hasLength(1));
      expect(find.text('Обновляем уведомления…'), findsNothing);
      expect(controller.notificationSyncResult?.succeeded, isTrue);
    },
  );

  testWidgets(
    'global opt-out waits for cancellation without requesting permission',
    (tester) async {
      controller.data = controller.data.copyWith(
        preferences: controller.data.preferences.copyWith(notifications: true),
      );
      await tester.runAsync(() => repository.save(controller.data));
      await mount(tester, const SettingsScreen(section: 'notifications'));
      await reveal(tester, toggle());
      await tester.tap(toggle());
      await until(tester, () => notifications.gates.length == 1);
      expect(controller.data.preferences.notifications, isFalse);
      expect(notifications.snapshots.single.preferences.notifications, isFalse);
      expect(controller.notificationSyncPending, isTrue);
      expect(notifications.permissionRequests, 0);
      notifications.succeed(0);
      await until(tester, () => !controller.notificationSyncPending);
      await tester.pumpAndSettle();
      expect(notifications.snapshots, hasLength(1));
      final saved = await tester.runAsync(repository.load);
      expect(saved!.preferences.notifications, isFalse);
    },
  );

  testWidgets(
    'scheduling failure is visible and settings retry performs no financial write',
    (tester) async {
      await mount(tester, const SettingsScreen(section: 'notifications'));
      await reveal(tester, toggle());
      await tester.tap(toggle());
      await until(tester, () => notifications.gates.length == 1);
      notifications.fail(0);
      await until(tester, () => !controller.notificationSyncPending);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('notification-sync-warning')),
        findsOneWidget,
      );
      expect(find.text(notificationSyncWarning), findsWidgets);
      final committed = await tester.runAsync(repository.load);
      expect(committed!.preferences.notifications, isTrue);
      final before = committed.toJson();
      // An independent SQLite connection detects every commit, even rewriting
      // identical rows. Equality of model JSON alone would miss that mistake.
      final observer = (await tester.runAsync(
        () => databaseFactoryFfi.openDatabase(
          '${directory.path}/ledger.db',
          options: OpenDatabaseOptions(singleInstance: false),
        ),
      ))!;
      addTearDown(observer.close);
      final versionBefore = await tester.runAsync(
        () => observer.rawQuery('PRAGMA data_version'),
      );
      await reveal(
        tester,
        find.byKey(const ValueKey('notification-sync-retry')),
      );
      await tester.tap(find.byKey(const ValueKey('notification-sync-retry')));
      await until(tester, () => notifications.gates.length == 2);
      expect(controller.notificationSyncPending, isTrue);
      notifications.succeed(1);
      await until(tester, () => !controller.notificationSyncPending);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('notification-sync-warning')),
        findsNothing,
      );
      expect(find.text('Уведомления обновлены.'), findsOneWidget);
      expect(notifications.snapshots, hasLength(2));
      expect(notifications.permissionRequests, 1);
      final after = await tester.runAsync(repository.load);
      expect(after!.toJson(), before);
      final versionAfter = await tester.runAsync(
        () => observer.rawQuery('PRAGMA data_version'),
      );
      expect(versionAfter, versionBefore);
    },
  );

  testWidgets(
    'new recurring save waits and closes after sync failure without duplicate creation',
    (tester) async {
      await mount(
        tester,
        const RecurringScreen(initialPaymentType: 'mandatory'),
      );
      await tester.tap(find.byTooltip('Добавить платёж'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        'Интернет',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Сумма'),
        '999',
      );
      await reveal(tester, find.text('Сохранить'), sheet: true);
      await tester.tap(find.text('Сохранить'));
      await until(tester, () => notifications.gates.length == 1);
      expect(controller.data.recurring, hasLength(1));
      expect(find.byType(BottomSheet), findsOneWidget);
      final saving = tester.widget<FilledButton>(
        find.byType(FilledButton).last,
      );
      expect(saving.onPressed, isNull);
      notifications.fail(0);
      await until(tester, () => find.byType(BottomSheet).evaluate().isEmpty);
      await tester.pumpAndSettle();
      expect(find.text(notificationSyncWarning), findsOneWidget);
      final committed = await tester.runAsync(repository.load);
      expect(committed!.recurring, hasLength(1));
      final id = committed.recurring.single.id;
      final retry = controller.retryNotificationSync();
      expect(notifications.gates, hasLength(2));
      notifications.succeed(1);
      await retry;
      expect(controller.data.recurring.single.id, id);
      final after = await tester.runAsync(repository.load);
      expect(after!.recurring, hasLength(1));
      expect(after.recurring.single.id, id);
      expect(notifications.snapshots, hasLength(2));
    },
  );

  testWidgets(
    'existing recurring edit waits for sync without scheduling twice',
    (tester) async {
      controller.data = controller.data.copyWith(recurring: [rule()]);
      await tester.runAsync(() => repository.save(controller.data));
      await mount(
        tester,
        const RecurringScreen(initialPaymentType: 'mandatory'),
      );
      await tester.tap(find.byKey(const ValueKey('payment-rule-rent')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        'Аренда новая',
      );
      await reveal(tester, find.text('Сохранить'), sheet: true);
      await tester.tap(find.text('Сохранить'));
      await until(tester, () => notifications.gates.length == 1);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(controller.data.recurring.single.name, 'Аренда новая');
      notifications.succeed(0);
      await until(tester, () => find.byType(BottomSheet).evaluate().isEmpty);
      await tester.pumpAndSettle();
      expect(notifications.snapshots, hasLength(1));
      final saved = await tester.runAsync(repository.load);
      expect(saved!.recurring.single.id, 'rent');
      expect(saved.recurring.single.name, 'Аренда новая');
    },
  );

  testWidgets(
    'delete commits once, awaits cancellation and closes with saved-data warning on failure',
    (tester) async {
      controller.data = controller.data.copyWith(recurring: [rule()]);
      await tester.runAsync(() => repository.save(controller.data));
      await mount(
        tester,
        const RecurringScreen(initialPaymentType: 'mandatory'),
      );
      await tester.tap(find.byKey(const ValueKey('payment-rule-rent')));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Удалить'), sheet: true);
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продолжить'));
      await until(tester, () => notifications.gates.length == 1);
      expect(controller.data.recurring, isEmpty);
      expect(notifications.snapshots.single.recurring, isEmpty);
      expect(find.byType(BottomSheet), findsOneWidget);
      notifications.fail(0);
      await until(tester, () => find.byType(BottomSheet).evaluate().isEmpty);
      await tester.pumpAndSettle();
      expect(find.text(notificationSyncWarning), findsOneWidget);
      final saved = await tester.runAsync(repository.load);
      expect(saved!.recurring, isEmpty);
      expect(notifications.snapshots, hasLength(1));
    },
  );
}
