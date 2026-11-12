import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/finance_background.dart';
import 'package:finora/presentation/widgets/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}

/// Finance 1.8 introduced a tinted gradient backdrop; the Apple polish
/// replaced it with one flat grouped-background color per theme (neutral
/// gray in light mode). Text stays readable on it in every theme.
void main() {
  for (final preset in AppTheme.presetNames.keys) {
    for (final brightness in Brightness.values) {
      test('$preset ${brightness.name}: flat, readable backdrop', () {
        final theme = AppTheme.build(brightness, preset);
        final b = theme.extension<FinanceBackdrop>()!;
        final base = theme.scaffoldBackgroundColor;
        expect([b.top, b.middle, b.bottom], everyElement(base));
        expect(b.glowA.a, 0);
        expect(b.glowB.a, 0);
        expect(
          _contrast(theme.colorScheme.onSurface, base),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(theme.colorScheme.onSurfaceVariant, base),
          greaterThanOrEqualTo(4.5),
        );
        if (brightness == Brightness.light) {
          // Close to iOS systemGroupedBackground, not a wash of the accent.
          final gray = const Color(0xFFF2F2F7);
          final shift = [
            (base.r - gray.r).abs(),
            (base.g - gray.g).abs(),
            (base.b - gray.b).abs(),
          ].reduce((a, c) => a > c ? a : c);
          expect(shift, lessThan(.06), reason: '$base');
        }
        // The running app keeps the preset's colors with a transparent
        // scaffold so the backdrop shows through.
        final app = AppTheme.app(brightness, preset);
        expect(app.scaffoldBackgroundColor, Colors.transparent);
        expect(app.colorScheme, theme.colorScheme);
      });
    }
  }

  testWidgets('background paints one flat color under its child', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.app(Brightness.dark, 'coffee'),
        home: const FinanceBackground(child: Text('содержимое')),
      ),
    );
    expect(find.text('содержимое'), findsOneWidget);
    final box = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('finance-backdrop')),
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.gradient, isNull);
    expect(
      decoration.color,
      AppTheme.build(Brightness.dark, 'coffee').scaffoldBackgroundColor,
    );
  });

  testWidgets('backdrop stands still: no frames when idle', (tester) async {
    // Even where endless ambient motion would be allowed, the backdrop does
    // not animate (1.11.1: a drifting backdrop re-ran every glass blur on
    // every frame and made phones lag).
    Motion.debugForceAmbient = true;
    addTearDown(() => Motion.debugForceAmbient = false);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.app(Brightness.dark, 'sunset'),
        home: const FinanceBackground(child: SizedBox()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
