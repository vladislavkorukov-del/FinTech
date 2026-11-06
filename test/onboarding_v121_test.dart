import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/onboarding.dart';
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

/// Finance 1.21: welcome screens on the first launch of a new install only.
void main() {
  sqfliteFfiInit();
  late Directory dir;
  late FinanceRepository repository;
  late FinanceController controller;
  setUp(() async {
    await initializeDateFormatting('ru');
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('finora-v121-welcome-');
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

  testWidgets('new install: hello, name, look, clean start, done', (
    tester,
  ) async {
    expect(controller.data.preferences.onboarded, isFalse);
    await mount(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Привет'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-start')));
    await tester.pumpAndSettle();
    expect(find.text('Как вас зовут?'), findsOneWidget);
    // «Продолжить» waits for a name.
    FilledButton next() => tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('onboarding-Продолжить')).first,
        matching: find.byType(FilledButton),
      ),
    );
    expect(next().onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-name')),
      'Влад',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('onboarding-Продолжить')).first);
    await flush(
      tester,
      () => find.text('Светлое или тёмное?').evaluate().isNotEmpty,
    );
    expect(controller.data.preferences.userName, 'Влад');
    expect(
      controller.data.members.firstWhere((m) => m.id == 'me').name,
      'Влад',
    );
    await tester.tap(find.byKey(const ValueKey('onboarding-theme-light')));
    await flush(tester, () => controller.data.preferences.theme == 'light');
    expect(controller.data.preferences.theme, 'light');
    await tester.tap(find.byKey(const ValueKey('onboarding-Продолжить')).last);
    await tester.pumpAndSettle();
    expect(find.text('Перенести данные?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-clean')));
    await flush(
      tester,
      () =>
          find.byKey(const ValueKey('onboarding-done')).evaluate().isNotEmpty &&
          !controller.data.demo,
    );
    expect(find.text('Всё готово, Влад!'), findsOneWidget);
    expect(controller.data.demo, isFalse);
    expect(controller.data.entries, isEmpty);
    expect(controller.data.accounts, isEmpty);
    expect(controller.data.preferences.userName, 'Влад');
    expect(controller.data.preferences.theme, 'light');
    await tester.tap(find.byKey(const ValueKey('onboarding-finish')));
    await flush(tester, () => controller.data.preferences.onboarded);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
    // Saved: the next launch goes straight in.
    final saved = (await tester.runAsync(repository.load))!;
    expect(saved.preferences.onboarded, isTrue);
    expect(saved.preferences.userName, 'Влад');
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Посмотреть на примере» keeps the demo; name can be skipped', (
    tester,
  ) async {
    await mount(tester);
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
    expect(find.text('Всё готово!'), findsOneWidget);
    expect(controller.data.demo, isTrue);
    expect(controller.data.entries, isNotEmpty);
    await tester.tap(find.byKey(const ValueKey('onboarding-finish')));
    await flush(tester, () => controller.data.preferences.onboarded);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('a reset opens it again, name filled in, example reloads', (
    tester,
  ) async {
    // An app in use with a name, then «Сбросить всё».
    await tester.runAsync(() async {
      await controller.mutate(
        (d) => d.copyWith(
          preferences: d.preferences.copyWith(
            onboarded: true,
            userName: 'Влад',
          ),
        ),
      );
    });
    await mount(tester);
    expect(find.byType(OnboardingScreen), findsNothing);
    await tester.runAsync(controller.resetAll);
    await tester.pumpAndSettle();
    expect(controller.data.preferences.onboarded, isFalse);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-start')));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text == 'Влад',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('onboarding-Продолжить')).first);
    await flush(
      tester,
      () => find.text('Светлое или тёмное?').evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('onboarding-Продолжить')).last);
    await tester.pumpAndSettle();
    expect(controller.data.accounts, isEmpty);
    await tester.tap(find.byKey(const ValueKey('onboarding-example')));
    await flush(
      tester,
      () =>
          find.byKey(const ValueKey('onboarding-done')).evaluate().isNotEmpty &&
          controller.data.demo,
    );
    expect(controller.data.demo, isTrue);
    expect(controller.data.entries, isNotEmpty);
    expect(controller.data.preferences.userName, 'Влад');
    expect(
      controller.data.members.firstWhere((m) => m.id == 'me').name,
      'Влад',
    );
    expect(find.text('Всё готово, Влад!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('button labels are never clipped', (tester) async {
    // 1.22.1: «Продолжить» was cut at the bottom on a phone.
    await mount(tester);
    void fits(String key) {
      final button = find.byKey(ValueKey(key)).first;
      final box = tester.getRect(button);
      final label = tester.getRect(
        find.descendant(of: button, matching: find.byType(Text)).first,
      );
      expect(label.top, greaterThanOrEqualTo(box.top), reason: key);
      expect(label.bottom, lessThanOrEqualTo(box.bottom), reason: key);
    }

    fits('onboarding-start');
    await tester.tap(find.byKey(const ValueKey('onboarding-start')));
    await tester.pumpAndSettle();
    fits('onboarding-Продолжить');
  });

  testWidgets('labels fit with large system text too', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await mount(tester);
    final button = find.byKey(const ValueKey('onboarding-start'));
    final box = tester.getRect(button);
    final label = tester.getRect(
      find.descendant(of: button, matching: find.byType(Text)).first,
    );
    expect(label.top, greaterThanOrEqualTo(box.top));
    expect(label.bottom, lessThanOrEqualTo(box.bottom));
    expect(tester.takeException(), isNull);
  });

  test('people who already use the app never see it', () {
    // Settings saved by earlier versions have no «onboarded» field.
    expect(AppPreferences.fromJson({'theme': 'dark'}).onboarded, isTrue);
    expect(const AppPreferences().onboarded, isTrue);
  });
}
