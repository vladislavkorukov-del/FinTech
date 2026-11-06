import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/onboarding.dart';
import 'package:finora/presentation/screens/settings.dart';
import 'package:finora/presentation/screens/tutorial.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Finance 1.25: the app tour after the welcome screens and in settings.
void main() {
  sqfliteFfiInit();
  late Directory dir;
  late FinanceRepository repository;
  late FinanceController controller;
  setUp(() async {
    await initializeDateFormatting('ru');
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('finora-v125-tour-');
    // A brand-new install: an empty database.
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/db',
    );
    controller = FinanceController(
      repository,
      _Quiet(),
      await repository.load(),
    );
  });
  tearDown(() async {
    controller.dispose();
    await repository.close();
    await dir.delete(recursive: true);
  });

  Future<void> flush(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 60 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinoraApp(controller: controller, requireDeviceSecurity: false),
    );
    await tester.pumpAndSettle();
  }

  Future<void> toDone(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('onboarding-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Пропустить'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-Продолжить')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-example')));
    await flush(
      tester,
      () => find.byKey(const ValueKey('onboarding-done')).evaluate().isNotEmpty,
    );
  }

  Finder title(int page) => find.descendant(
    of: find.byKey(ValueKey('tutorial-page-$page')),
    matching: find.textContaining('из ${TutorialScreen.pageCount}'),
  );

  testWidgets('the whole tour, page by page, then the main screen', (
    tester,
  ) async {
    await mount(tester);
    await toDone(tester);
    expect(find.byKey(const ValueKey('onboarding-tour')), findsOneWidget);
    expect(find.text('Пропустить обучение'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-tour')));
    await tester.pumpAndSettle();
    expect(find.byType(TutorialScreen), findsOneWidget);
    // Not finished while the tour is open.
    expect(controller.data.preferences.onboarded, isFalse);
    for (var i = 0; i < TutorialScreen.pageCount - 1; i++) {
      expect(title(i), findsOneWidget, reason: 'page $i');
      expect(tester.takeException(), isNull, reason: 'page $i');
      await tester.tap(find.byKey(const ValueKey('tutorial-next')));
      await tester.pumpAndSettle();
    }
    // Back works, then forward again.
    await tester.tap(find.byKey(const ValueKey('tutorial-back')));
    await tester.pumpAndSettle();
    expect(title(TutorialScreen.pageCount - 2), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Ваши данные — только у вас'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tutorial-done')));
    await flush(tester, () => controller.data.preferences.onboarded);
    expect(find.byType(TutorialScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tour can be skipped from any page, or refused', (
    tester,
  ) async {
    await mount(tester);
    await toDone(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding-tour')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await tester.pumpAndSettle();
    expect(title(2), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tutorial-skip')));
    await flush(tester, () => controller.data.preferences.onboarded);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Пропустить обучение» goes straight in', (tester) async {
    await mount(tester);
    await toDone(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding-finish')));
    await flush(tester, () => controller.data.preferences.onboarded);
    expect(find.byType(TutorialScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  for (final (name, size, scale, dark) in [
    ('small phone, large text', const Size(360, 700), 1.5, false),
    ('dark', const Size(412, 915), 1.0, true),
  ]) {
    testWidgets('every page fits: $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const TutorialScreen(),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < TutorialScreen.pageCount; i++) {
        expect(tester.takeException(), isNull, reason: 'page $i');
        if (i < TutorialScreen.pageCount - 1) {
          await tester.tap(find.byKey(const ValueKey('tutorial-next')));
          await tester.pumpAndSettle();
        }
      }
      expect(find.byKey(const ValueKey('tutorial-done')), findsOneWidget);
    });
  }

  testWidgets('settings open the tour again', (tester) async {
    controller = FinanceController(
      repository,
      _Quiet(),
      (await tester.runAsync(repository.load))!,
    );
    await tester.runAsync(
      () => controller.mutate(
        (d) => d.copyWith(preferences: d.preferences.copyWith(onboarded: true)),
      ),
    );
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceScope(
          controller: controller,
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final item = find.text('Что умеет Finora');
    await tester.scrollUntilVisible(
      item,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(find.byType(TutorialScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tutorial-skip')));
    await tester.pumpAndSettle();
    expect(find.byType(TutorialScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
