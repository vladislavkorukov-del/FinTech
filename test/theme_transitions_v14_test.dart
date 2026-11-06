import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/settings.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _QuietNotifications extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late FinanceRepository repository;
  late FinanceController controller;
  late Map<String, dynamic> original;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await initializeDateFormatting('ru');
    directory = await Directory.systemTemp.createTemp('finora-themes-v14-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/ledger.db',
    );
    final data = await repository.load();
    original = data.toJson()..remove('preferences');
    controller = FinanceController(repository, _QuietNotifications(), data);
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
  });

  test(
    'all visual styles persist through SQLite restart and JSON import',
    () async {
      for (final mode in ['light', 'dark', 'system']) {
        for (final preset in AppTheme.presetNames.keys) {
          final next = controller.data.preferences.copyWith(
            accent: preset,
            theme: mode,
          );
          await controller.preferences(next);
          final backup = await repository.exportJson();
          await repository.close();
          repository = await FinanceRepository.open(
            factory: databaseFactoryFfi,
            path: '${directory.path}/ledger.db',
          );
          await repository.importJson(backup);
          final restored = await repository.load();
          expect(
            restored.preferences.toJson(),
            next.toJson(),
            reason: '$preset/$mode',
          );
          expect(restored.toJson()..remove('preferences'), original);
          controller.dispose();
          controller = FinanceController(
            repository,
            _QuietNotifications(),
            restored,
          );
        }
      }
    },
  );

  test(
    'legacy accents remain valid and invalid settings fail atomically',
    () async {
      for (final preset in ['gold', 'lavender', 'blue']) {
        await controller.preferences(
          controller.data.preferences.copyWith(accent: preset),
        );
        expect((await repository.load()).preferences.accent, preset);
      }
      final saved = (await repository.load()).toJson();
      await expectLater(
        controller.preferences(
          controller.data.preferences.copyWith(accent: 'unknown'),
        ),
        throwsFormatException,
      );
      expect((await repository.load()).toJson(), saved);
    },
  );

  testWidgets(
    'Settings changes all twelve styles in light dark and system with animated frames',
    (tester) async {
      tester.view.physicalSize = const Size(430, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        FinoraApp(controller: controller, requireDeviceSecurity: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ещё'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Настройки'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      Future<void> select(
        String label,
        String value,
        bool Function() ready,
      ) async {
        final before = controller.data;
        final field = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == label,
        );
        await Scrollable.ensureVisible(tester.element(field), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(field);
        await tester.pumpAndSettle();
        final item = find.text(value).last;
        await tester.ensureVisible(item);
        await tester.tap(item);
        await tester.pump();
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (identical(controller.data, before) || !ready()) {
            if (DateTime.now().isAfter(deadline)) {
              throw TestFailure('Settings did not persist $label/$value');
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pump();
        // Exercise real ThemeData.lerp frames, not only the settled endpoints.
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 35));
          expect(
            tester.takeException(),
            isNull,
            reason: '$label/$value frame $frame',
          );
        }
        await tester.pumpAndSettle();
        expect(find.textContaining('Некорректные настройки'), findsNothing);
      }

      for (final mode in ['light', 'dark', 'system']) {
        await select(
          'Тема',
          {
            'light': 'Светлая',
            'dark': 'Тёмная',
            'system': 'Как в системе',
          }[mode]!,
          () => controller.data.preferences.theme == mode,
        );
        for (final preset in AppTheme.presetNames.entries) {
          await select(
            'Визуальный стиль',
            preset.value,
            () => controller.data.preferences.accent == preset.key,
          );
          final currentTheme = Theme.of(
            tester.element(find.byType(SettingsScreen)),
          );
          // The running app paints the preset's backdrop over a transparent
          // scaffold (1.8); cards and the backdrop come from the preset.
          final expected = AppTheme.build(currentTheme.brightness, preset.key);
          expect(currentTheme.scaffoldBackgroundColor, Colors.transparent);
          expect(
            currentTheme.colorScheme.surface,
            expected.colorScheme.surface,
          );
          expect(
            currentTheme.extension<FinanceBackdrop>()!.top,
            expected.extension<FinanceBackdrop>()!.top,
          );
          if (mode == 'system') {
            for (final brightness in [Brightness.dark, Brightness.light]) {
              tester.platformDispatcher.platformBrightnessTestValue =
                  brightness;
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 75));
              expect(
                tester.takeException(),
                isNull,
                reason: '${preset.key}/system/$brightness',
              );
              await tester.pumpAndSettle();
              expect(
                Theme.of(
                  tester.element(find.byType(SettingsScreen)),
                ).brightness,
                brightness,
              );
            }
          }
          // Coffee has additional component overrides. Traverse both edges
          // between it and each preset while SettingsScreen remains mounted.
          await select(
            'Визуальный стиль',
            AppTheme.presetNames['coffee']!,
            () => controller.data.preferences.accent == 'coffee',
          );
        }
      }
      await select(
        'Визуальный стиль',
        AppTheme.presetNames['royal']!,
        () => controller.data.preferences.accent == 'royal',
      );
      final expectedPreferences = controller.data.preferences.toJson();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      final persisted = await tester.runAsync(() async {
        await repository.close();
        repository = await FinanceRepository.open(
          factory: databaseFactoryFfi,
          path: '${directory.path}/ledger.db',
        );
        final data = await repository.load();
        controller = FinanceController(repository, _QuietNotifications(), data);
        return data;
      });
      expect(persisted!.preferences.toJson(), expectedPreferences);
      expect(persisted.preferences.theme, 'system');
      expect(persisted.preferences.accent, 'royal');
      expect(persisted.toJson()..remove('preferences'), original);
      await tester.pumpWidget(
        FinoraApp(controller: controller, requireDeviceSecurity: false),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
