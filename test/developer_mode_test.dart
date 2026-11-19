import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/monetization.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/batch_entries_screen.dart';
import 'package:finora/presentation/screens/developer_screen.dart';
import 'package:finora/presentation/screens/settings.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/finora_drawer.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Developer mode (three long presses on the version) and the paid
/// features prepared for later.
void main() {
  test('nothing is paid until the paywall is enforced', () {
    const free = DeveloperSettings();
    for (final f in PaidFeature.catalog) {
      expect(Entitlements.allows(free, f.id), isTrue);
    }
    const marked = DeveloperSettings(paidFeatures: {PaidFeature.batchEntries});
    expect(Entitlements.allows(marked, PaidFeature.batchEntries), isTrue);
    final enforced = marked.copyWith(enforcePaywall: true);
    expect(Entitlements.allows(enforced, PaidFeature.batchEntries), isFalse);
    expect(Entitlements.allows(enforced, PaidFeature.budgets), isTrue);
    expect(
      Entitlements.allows(
        enforced.copyWith(simulatedPlus: true),
        'batch_entries',
      ),
      isTrue,
    );
    expect(Entitlements.locked(enforced).map((f) => f.id), ['batch_entries']);
    // Saved with the preferences; unknown ids are dropped.
    final json = enforced.toJson()
      ..['paidFeatures'] = ['batch_entries', 'no_such'];
    final back = DeveloperSettings.fromJson(json);
    expect(back.enforcePaywall, isTrue);
    expect(back.paidFeatures, {'batch_entries'});
    final prefs = AppPreferences.fromJson(
      const AppPreferences(
        developer: DeveloperSettings(enabled: true),
      ).toJson(),
    );
    expect(prefs.developer.enabled, isTrue);
    // Old preferences without the key.
    expect(AppPreferences.fromJson(const {}).developer.enabled, isFalse);
  });

  test('the store seam never charges today', () async {
    const store = NoPurchaseProvider();
    expect(await store.products(), isEmpty);
    expect(await store.buy('finora_plus'), isA<PurchaseUnavailable>());
    expect(await store.hasPlus(), isFalse);
  });

  late FinanceController c;
  late FinanceRepository repo;
  Future<void> start(WidgetTester tester, Widget home) async {
    sqfliteFfiInit();
    await initializeDateFormatting('ru');
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('finora-dev-'),
    );
    repo = (await tester.runAsync(
      () => FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir!.path}/a.db',
      ),
    ))!;
    await tester.runAsync(
      () => repo.save(createDemoData(DateTime.now()).copyWith(demo: false)),
    );
    c = FinanceController(repo, _Quiet(), (await tester.runAsync(repo.load))!);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.app(Brightness.light, 'tropic'),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 150 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.runAsync(repo.close);
  }

  testWidgets('three taps on Finora in «О приложении» open developer mode', (
    tester,
  ) async {
    await start(tester, const SettingsScreen(section: 'about'));
    final finora = find.byKey(const ValueKey('about-finora-taps'));
    for (var i = 0; i < 3; i++) {
      await tester.tap(finora);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester, () => c.data.preferences.developer.enabled);
    expect(find.byType(DeveloperScreen), findsOneWidget);
    await stop(tester);
  });

  testWidgets('three long presses on the version open developer mode', (
    tester,
  ) async {
    await start(tester, const SettingsScreen(section: 'about'));
    final version = find.byKey(const ValueKey('assistant-developer-unlock'));
    await tester.ensureVisible(version);
    for (var i = 0; i < 3; i++) {
      final gesture = await tester.startGesture(tester.getCenter(version));
      // The unlock reads the wall clock: a real long press.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1600)),
      );
      await gesture.up();
      await tester.pump();
    }
    await settle(tester, () => c.data.preferences.developer.enabled);
    expect(c.data.preferences.developer.enabled, isTrue);
    expect(find.byType(DeveloperScreen), findsOneWidget);
    // Mark «Несколько операций» paid and enforce.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('dev-paid-batch_entries')),
        matching: find.byType(Switch),
      ),
    );
    await settle(
      tester,
      () => c.data.preferences.developer.paidFeatures.isNotEmpty,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('dev-enforce')),
        matching: find.byType(Switch),
      ),
    );
    await settle(tester, () => c.data.preferences.developer.enforcePaywall);
    expect(
      Entitlements.allows(c.data.preferences.developer, 'batch_entries'),
      isFalse,
    );
    await stop(tester);
  });

  testWidgets('a locked screen offers Plus; test Plus opens it', (
    tester,
  ) async {
    await start(tester, const BatchEntriesScreen());
    await tester.runAsync(
      () => c.preferences(
        c.data.preferences.copyWith(
          developer: const DeveloperSettings(
            enabled: true,
            enforcePaywall: true,
            paidFeatures: {PaidFeature.batchEntries},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('feature-locked-batch_entries')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('feature-locked-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paywall')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paywall-test-plus')));
    await settle(tester, () => c.data.preferences.developer.simulatedPlus);
    expect(find.byKey(const ValueKey('batch-save')), findsOneWidget);
    await stop(tester);
  });

  testWidgets('the side panel: functions open, settings folded', (
    tester,
  ) async {
    await start(
      tester,
      Scaffold(body: FinoraDrawer(current: 0, onSelect: (_) {})),
    );
    expect(find.byKey(const ValueKey('drawer-shopping')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('drawer-settings-appearance')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('drawer-settings-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('drawer-settings-appearance')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('drawer-functions-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drawer-shopping')), findsNothing);
    // Back as it was, for the other tests of this run.
    await tester.tap(find.byKey(const ValueKey('drawer-functions-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer-settings-toggle')));
    await tester.pumpAndSettle();
    await stop(tester);
  });
}
