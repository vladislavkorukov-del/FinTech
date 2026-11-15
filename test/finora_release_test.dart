import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/app_version.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/release_celebration.dart';
import 'package:finora/presentation/whats_new.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

/// Finora Release: version 1.0.0 for people, a growing build number for
/// Android (it installs over every earlier version), and a celebration on
/// the first launch.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('ru');
  });

  test(
    'the release is called Finora Release, 1.0.0; the build number grows',
    () {
      expect(appName, 'Finora Release');
      expect(appVersion, '1.0.0');
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(
        r'^version: (\d+\.\d+\.\d+)\+(\d+)$',
        multiLine: true,
      ).firstMatch(pubspec)!;
      expect(m.group(1), appVersion);
      // Earlier versions reached 117: Android installs only a higher code.
      expect(int.parse(m.group(2)!), greaterThan(117));
      expect(const AppPreferences().releaseCelebrated, isFalse);
      expect(
        AppPreferences.fromJson(
          const AppPreferences(releaseCelebrated: true).toJson(),
        ).releaseCelebrated,
        isTrue,
      );
    },
  );

  testWidgets('the first launch celebrates once, then «Что нового» is quiet', (
    tester,
  ) async {
    ReleaseCelebration.enabled = true;
    addTearDown(() => ReleaseCelebration.enabled = false);
    late Directory temp;
    late FinanceRepository repo;
    late FinanceController c;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('finora-release-');
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/db',
      );
      await repo.save(
        const FinanceData(
          members: [Member(id: 'me', name: 'Я')],
          preferences: AppPreferences(onboarded: true, seenVersion: '2.3.0'),
        ),
      );
      c = FinanceController(repo, _Quiet(), await repo.load());
    });
    late BuildContext ctx;
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    final shown = ReleaseCelebration.check(ctx);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('release-celebration')), findsOneWidget);
    expect(find.text('Finora Release'), findsOneWidget);
    expect(find.text('Версия 1.0.0'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('release-start')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('release-start')));
    for (var k = 0; k < 10; k++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('release-celebration')), findsNothing);
    // The preferences are written to the base (real time).
    for (var k = 0; k < 20 && !c.data.preferences.releaseCelebrated; k++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(await tester.runAsync(() => shown), isTrue);
    expect(c.data.preferences.releaseCelebrated, isTrue);
    expect(c.data.preferences.seenVersion, appVersion);
    expect(await tester.runAsync(() => ReleaseCelebration.check(ctx)), isFalse);
    expect(await tester.runAsync(() => WhatsNew.check(ctx)), isFalse);
  });
}
