import 'package:finora/domain/style_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/theme/reference_palettes.dart';
import 'package:finora/presentation/theme/icon_catalog.dart';
import 'package:finora/presentation/screens/management.dart';
import 'package:finora/presentation/widgets/common.dart' show SectionTitle;

double contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  group('Premium palette and readable controls', () {
    test('removed Lime opens in Coffee (1.55)', () {
      for (final b in Brightness.values) {
        expect(
          AppTheme.build(b, 'lime').colorScheme,
          AppTheme.build(b, 'coffee').colorScheme,
        );
      }
    });
    test('every preset keeps text and buttons accessible in both themes', () {
      expect(AppTheme.presetNames.keys, visualStyleIds);
      for (final preset in AppTheme.presetNames.keys) {
        for (final brightness in Brightness.values) {
          final theme = AppTheme.build(brightness, preset);
          final scheme = theme.colorScheme;
          expect(
            contrast(scheme.primary, scheme.onPrimary),
            greaterThanOrEqualTo(4.5),
            reason: '$preset $brightness accent',
          );
          expect(
            contrast(scheme.onSurface, scheme.surface),
            greaterThanOrEqualTo(7),
          );
          expect(
            contrast(scheme.onSurfaceVariant, scheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(
              theme.textButtonTheme.style!.foregroundColor!.resolve({})!,
              scheme.surface,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(
              theme.outlinedButtonTheme.style!.foregroundColor!.resolve({})!,
              theme.scaffoldBackgroundColor,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(
              theme.filledButtonTheme.style!.foregroundColor!.resolve({})!,
              theme.filledButtonTheme.style!.backgroundColor!.resolve({})!,
            ),
            greaterThanOrEqualTo(
              preset == 'coffee' || referencePalettes.containsKey(preset)
                  ? 4.5
                  : 7,
            ),
          );
        }
      }
    });
    test(
      'coffee uses warm surfaces and taupe buttons, highlighting only selection',
      () {
        final dark = AppTheme.build(Brightness.dark, 'coffee');
        final light = AppTheme.build(Brightness.light, 'coffee');
        expect(dark.scaffoldBackgroundColor, const Color(0xFF0F0C08));
        expect(dark.colorScheme.surface, const Color(0xFF231A12));
        expect(dark.colorScheme.onSurface, const Color(0xFFF7F5F1));
        expect(dark.colorScheme.primary, const Color(0xFFFBE88C));
        expect(dark.colorScheme.secondary, const Color(0xFF886B4B));
        expect(
          dark.extension<FinanceColors>()!.expense,
          const Color(0xFFD67C7E),
        );
        for (final theme in [dark, light]) {
          expect(
            theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
            const Color(0xFF886B4B),
          );
          expect(
            theme.filledButtonTheme.style!.foregroundColor!.resolve({}),
            const Color(0xFFF7F5F1),
          );
          expect(
            theme.segmentedButtonTheme.style!.backgroundColor!.resolve({
              WidgetState.selected,
            }),
            const Color(0xFFFBE88C),
          );
          expect(
            theme.segmentedButtonTheme.style!.backgroundColor!.resolve({}),
            theme.colorScheme.surface,
          );
          expect(
            theme.datePickerTheme.backgroundColor,
            theme.colorScheme.surface,
          );
          expect(
            theme.datePickerTheme.dayBackgroundColor!.resolve({
              WidgetState.selected,
            }),
            const Color(0xFFFBE88C),
          );
          expect(
            theme.datePickerTheme.dayForegroundColor!.resolve({
              WidgetState.selected,
            }),
            const Color(0xFF0F0C08),
          );
          expect(theme.dialogTheme.backgroundColor, theme.colorScheme.surface);
          final colors = theme.extension<FinanceColors>()!;
          expect(
            contrast(colors.expense, theme.colorScheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(colors.income, theme.colorScheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(colors.iconForeground, colors.iconBackground),
            greaterThanOrEqualTo(4.5),
          );
        }
      },
    );

    test('legacy color names keep their data but render the lime palette', () {
      for (final legacy in ['gold', 'lavender', 'blue', 'unknown']) {
        expect(AppTheme.accent(legacy), AppTheme.lime);
      }
    });
  });

  group('Stable exhaustive icon catalog', () {
    test(
      'all 36 stored legacy indices still identify their original icons',
      () {
        const legacy = [
          Icons.shopping_basket_outlined,
          Icons.restaurant_outlined,
          Icons.directions_bus_outlined,
          Icons.directions_car_outlined,
          Icons.home_outlined,
          Icons.bolt_outlined,
          Icons.favorite_border_rounded,
          Icons.medication_outlined,
          Icons.movie_outlined,
          Icons.subscriptions_outlined,
          Icons.shopping_bag_outlined,
          Icons.checkroom_outlined,
          Icons.card_giftcard_outlined,
          Icons.flight_outlined,
          Icons.school_outlined,
          Icons.child_care_outlined,
          Icons.pets_outlined,
          Icons.receipt_long_outlined,
          Icons.credit_card_outlined,
          Icons.more_horiz_rounded,
          Icons.work_outline_rounded,
          Icons.laptop_outlined,
          Icons.storefront_outlined,
          Icons.percent_rounded,
          Icons.trending_up_rounded,
          Icons.undo_rounded,
          Icons.wallet_outlined,
          Icons.savings_outlined,
          Icons.account_balance_outlined,
          Icons.beach_access_outlined,
          Icons.devices_outlined,
          Icons.shield_outlined,
          Icons.sports_esports_outlined,
          Icons.fitness_center_outlined,
          Icons.coffee_outlined,
          Icons.music_note_outlined,
        ];
        expect(iconChoices.take(36), legacy);
        for (var index = 0; index < 36; index++) {
          expect(categoryIcon(index), legacy[index]);
        }
      },
    );
    test(
      'broad static catalog has unique keys and stable position metadata',
      () {
        expect(iconChoices.length, greaterThan(2000));
        expect(iconCatalog.length, iconChoices.length);
        expect(
          iconCatalog.map((entry) => entry.name).toSet().length,
          iconCatalog.length,
        );
        for (var i = 0; i < iconCatalog.length; i++) {
          expect(iconCatalog[i].index, i);
          expect(iconCatalog[i].icon, iconChoices[i]);
          expect(iconGroups, contains(iconCatalog[i].group));
        }
        expect(iconGroups.length, greaterThanOrEqualTo(15));
      },
    );
    test('Russian and English searches cover common household spending', () {
      for (final query in [
        'стоматолог',
        'dentist',
        'ипотека',
        'mortgage',
        'ногти',
        'nails',
        'маникюр',
        'такси',
        'taxi',
        'бензин',
        'fuel',
        'страхование',
        'insurance',
        'питомцы',
        'pet',
        'путешествия',
        'travel',
      ]) {
        expect(searchFinanceIcons(query), isNotEmpty, reason: query);
      }
    });
    test('search normalizes ё/case/whitespace and matches all query words', () {
      expect(
        searchFinanceIcons('  САМОЛЁТ  ').map((e) => e.name),
        contains('flight_outlined'),
      );
      expect(
        searchFinanceIcons('  NAILS   manicure ').map((e) => e.name),
        contains('spa_outlined'),
      );
      expect(
        searchFinanceIcons('local_taxi').map((e) => e.name),
        contains('local_taxi_outlined'),
      );
      expect(
        searchFinanceIcons('машина авто').map((e) => e.name),
        contains('directions_car_outlined'),
      );
      expect(searchFinanceIcons('стоматолог', group: 'health'), isNotEmpty);
      expect(searchFinanceIcons('стоматолог', group: 'food'), isEmpty);
      expect(searchFinanceIcons('несуществующаякатегория'), isEmpty);
    });
  });

  testWidgets(
    'caption-only SectionTitle is text rather than a disabled action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light, 'lime'),
          home: const Scaffold(body: SectionTitle('Обзор', action: 'Март')),
        ),
      );
      expect(find.text('Март'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large picker lazily builds cells and saves searched icon/color',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      (int, int)? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light, 'lime'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showIconPicker(
                      context,
                      icon: 0,
                      color: 0xFFC5E768,
                    );
                  },
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(find.byType(SliverGrid), findsOneWidget);
      final builtCells = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('catalog-icon-'),
      );
      expect(builtCells.evaluate().length, lessThan(150));
      expect(builtCells.evaluate().length, greaterThan(0));
      await tester.enterText(
        find.byKey(const ValueKey('icon-search')),
        'стоматолог',
      );
      await tester.pumpAndSettle();
      final target = iconCatalog.firstWhere(
        (entry) => entry.name == 'medical_services_outlined',
      );
      final cell = find.byKey(ValueKey('catalog-icon-${target.index}'));
      await tester.ensureVisible(cell);
      await tester.tap(cell);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выбрать'));
      await tester.pumpAndSettle();
      expect(result, (target.index, 0xFFC5E768));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('picker remains usable with keyboard on small landscape screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 130);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark, 'midnight'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () =>
                    showIconPicker(context, icon: 35, color: 0xFFC5E768),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Выбрать'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('icon-picker-scroll')), findsNothing);
  });
}
