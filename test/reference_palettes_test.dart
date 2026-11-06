import 'package:finora/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// These are the supplied reference colors, independent of the theme builder.
const references = <String, List<Color>>{
  'harbor': [
    Color(0xFF0B132B),
    Color(0xFF1C2541),
    Color(0xFF3A506B),
    Color(0xFF5BC0DE),
    Color(0xFFF4D6B0),
    Color(0xFFD97706),
  ],
  'forest': [
    Color(0xFF0B0F0D),
    Color(0xFF1F2A1F),
    Color(0xFF3E5A3E),
    Color(0xFF8CA98C),
    Color(0xFFD9C7A3),
    Color(0xFFB08D57),
  ],
  'velvet': [
    Color(0xFF0E0B1D),
    Color(0xFF2A1E4D),
    Color(0xFF5A3B8C),
    Color(0xFF8B7CC7),
    Color(0xFFC9C2E3),
    Color(0xFF3A3A52),
  ],
  'aurora': [
    Color(0xFF1A1A1F),
    Color(0xFF2D2B55),
    Color(0xFF6A5ACD),
    Color(0xFFA678B9),
    Color(0xFFF0D9B5),
    Color(0xFFF4A62A),
  ],
  'royal': [
    Color(0xFF09091F),
    Color(0xFF191970),
    Color(0xFF2D2D88),
    Color(0xFFFB5607),
    Color(0xFFF7F5F1),
    Color(0xFFFFA775),
  ],
};

double contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  test(
    'reference themes (5 + 14 in 1.9) extend, rather than replace, seven presets',
    () {
      expect(AppTheme.presetNames.length, 26);
      expect(
        AppTheme.presetNames.keys,
        containsAll([
          'coffee',
          'lime',
          'electric',
          'sage',
          'graphite',
          'paper',
          'midnight',
          ...references.keys,
        ]),
      );
      expect(AppTheme.presetNames['velvet'], contains('Lavender'));
      expect(AppTheme.presetNames['royal'], contains('Nitro'));
      expect(AppTheme.accent('lavender'), AppTheme.lime);
      expect(AppTheme.accent('gold'), AppTheme.lime);
      expect(AppTheme.accent('blue'), AppTheme.lime);
    },
  );
  for (final entry in references.entries) {
    final name = entry.key;
    final colors = entry.value;
    test('$name uses all reference colors as actual component tokens', () {
      final theme = AppTheme.build(Brightness.dark, name);
      expect(theme.scaffoldBackgroundColor, colors[0]);
      expect(theme.colorScheme.surface, colors[1]);
      expect(theme.colorScheme.secondary, colors[2]);
      expect(theme.chipTheme.selectedColor, colors[3]);
      expect(theme.colorScheme.onSurface, colors[4]);
      expect(theme.colorScheme.tertiary, colors[5]);
      expect(AppTheme.accent(name), colors[3]);
    });
    for (final brightness in Brightness.values) {
      test(
        '$name $brightness readable finances, buttons and selected controls',
        () {
          final theme = AppTheme.build(brightness, name);
          final scheme = theme.colorScheme;
          final finance = theme.extension<FinanceColors>()!;
          for (final background in [
            theme.scaffoldBackgroundColor,
            scheme.surface,
          ]) {
            for (final foreground in [
              scheme.onSurface,
              scheme.onSurfaceVariant,
              finance.income,
              finance.expense,
              scheme.primary,
            ]) {
              expect(
                contrast(foreground, background),
                greaterThanOrEqualTo(4.5),
                reason: '$name $brightness text on surface',
              );
            }
          }
          expect(
            contrast(scheme.onSurface, theme.inputDecorationTheme.fillColor!),
            greaterThanOrEqualTo(4.5),
            reason: '$name $brightness typed input',
          );
          expect(
            contrast(
              theme.inputDecorationTheme.labelStyle!.color!,
              theme.inputDecorationTheme.fillColor!,
            ),
            greaterThanOrEqualTo(4.5),
            reason: '$name $brightness input label',
          );
          expect(
            contrast(finance.iconForeground, finance.iconBackground),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(finance.brandForeground, finance.brandBackground),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.primary, scheme.onPrimary),
            greaterThanOrEqualTo(4.5),
          );
          for (final style in [
            theme.filledButtonTheme.style!,
            theme.elevatedButtonTheme.style!,
          ]) {
            expect(
              contrast(
                style.foregroundColor!.resolve({})!,
                style.backgroundColor!.resolve({})!,
              ),
              greaterThanOrEqualTo(4.5),
            );
          }
          for (final style in [
            theme.outlinedButtonTheme.style!,
            theme.textButtonTheme.style!,
          ]) {
            expect(
              contrast(style.foregroundColor!.resolve({})!, scheme.surface),
              greaterThanOrEqualTo(4.5),
            );
          }
          final selected = {WidgetState.selected};
          expect(
            contrast(
              theme.segmentedButtonTheme.style!.foregroundColor!.resolve(
                selected,
              )!,
              theme.segmentedButtonTheme.style!.backgroundColor!.resolve(
                selected,
              )!,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(
              theme.switchTheme.thumbColor!.resolve(selected)!,
              theme.switchTheme.trackColor!.resolve(selected)!,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(
              theme.datePickerTheme.dayForegroundColor!.resolve(selected)!,
              theme.datePickerTheme.dayBackgroundColor!.resolve(selected)!,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(theme.canvasColor, scheme.surface);
          expect(
            theme.menuTheme.style!.backgroundColor!.resolve({}),
            scheme.surface,
          );
          expect(
            theme.dropdownMenuTheme.menuStyle!.backgroundColor!.resolve({}),
            scheme.surface,
          );
          expect(theme.dialogTheme.backgroundColor, scheme.surface);
          expect(theme.bottomSheetTheme.backgroundColor, scheme.surface);
          expect(theme.popupMenuTheme.color, scheme.surface);
          expect(theme.datePickerTheme.backgroundColor, scheme.surface);
          expect(theme.timePickerTheme.backgroundColor, scheme.surface);
          expect(theme.navigationBarTheme.backgroundColor, scheme.surface);
        },
      );
    }
  }
  test('Coffee retains its existing dark and light appearance', () {
    final dark = AppTheme.build(Brightness.dark, 'coffee');
    final light = AppTheme.build(Brightness.light, 'coffee');
    expect(dark.scaffoldBackgroundColor, const Color(0xFF0F0C08));
    expect(dark.colorScheme.surface, const Color(0xFF231A12));
    expect(dark.colorScheme.primary, const Color(0xFFFBE88C));
    expect(
      dark.filledButtonTheme.style!.backgroundColor!.resolve({}),
      const Color(0xFF886B4B),
    );
    expect(light.scaffoldBackgroundColor, const Color(0xFFF7F5F1));
    expect(light.colorScheme.surface, const Color(0xFFFEFCF8));
    expect(light.extension<FinanceColors>()!.expense, const Color(0xFF9F4448));
  });
  testWidgets(
    'reference theme follows system brightness and themes real date dialog',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light, 'harbor'),
          darkTheme: AppTheme.build(Brightness.dark, 'harbor'),
          themeMode: ThemeMode.system,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                  initialDate: DateTime(2026, 11, 5),
                ),
                child: const Text('Выбрать дату'),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        isNull,
      );
      expect(
        Theme.of(
          tester.element(find.text('Выбрать дату')),
        ).scaffoldBackgroundColor,
        const Color(0xFF0B132B),
      );
      await tester.tap(find.text('Выбрать дату'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      final dialogTheme = Theme.of(
        tester.element(find.byType(DatePickerDialog)),
      );
      expect(
        dialogTheme.datePickerTheme.backgroundColor,
        const Color(0xFF1C2541),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Выбрать дату'))).brightness,
        Brightness.light,
      );
      expect(
        Theme.of(
          tester.element(find.text('Выбрать дату')),
        ).scaffoldBackgroundColor.computeLuminance(),
        greaterThan(.8),
      );
    },
  );
}
