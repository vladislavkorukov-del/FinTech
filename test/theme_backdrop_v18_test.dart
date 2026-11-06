import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/finance_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}

/// Finance 1.8: themes paint a tinted gradient with color glows instead of a
/// flat (often black) background; text stays readable on all of it.
void main() {
  for (final preset in AppTheme.presetNames.keys) {
    for (final brightness in Brightness.values) {
      test('$preset ${brightness.name}: tinted, readable backdrop', () {
        final theme = AppTheme.build(brightness, preset);
        final b = theme.extension<FinanceBackdrop>()!;
        final base = theme.scaffoldBackgroundColor;
        // The top of the screen carries the palette's color, not plain base.
        expect(b.top, isNot(base));
        final shift = [
          (b.top.r - base.r).abs(),
          (b.top.g - base.g).abs(),
          (b.top.b - base.b).abs(),
        ].reduce((a, c) => a > c ? a : c);
        expect(shift, greaterThan(.04), reason: 'top is visibly tinted');
        expect(b.glowA.a, greaterThan(0));
        expect(b.glowB.a, greaterThan(0));
        final ink = theme.colorScheme.onSurface;
        for (final c in [b.top, b.middle, b.bottom]) {
          expect(_contrast(ink, c), greaterThanOrEqualTo(4.5), reason: '$c');
        }
        // The running app keeps the preset's colors with a transparent
        // scaffold so the backdrop shows through.
        final app = AppTheme.app(brightness, preset);
        expect(app.scaffoldBackgroundColor, Colors.transparent);
        expect(app.colorScheme, theme.colorScheme);
      });
    }
  }

  testWidgets('background paints gradient and glows under its child', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.app(Brightness.dark, 'coffee'),
        home: const FinanceBackground(child: Text('содержимое')),
      ),
    );
    expect(find.byKey(const ValueKey('finance-backdrop')), findsOneWidget);
    expect(find.text('содержимое'), findsOneWidget);
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey('finance-backdrop')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final gradient = (box.decoration as BoxDecoration).gradient!;
    expect(gradient, isA<LinearGradient>());
    expect(gradient.colors.toSet(), hasLength(greaterThan(1)));
  });
}
