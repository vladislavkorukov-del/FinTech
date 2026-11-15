import 'dart:io';

import 'package:finora/presentation/page_transitions.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/whats_new.dart';
import 'package:finora/presentation/widgets/finance_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('открытая страница — со своим фоном, не просвечивает', (
    tester,
  ) async {
    final theme = withFinoraTransitions(
      AppTheme.app(Brightness.dark, 'emerald'),
    );
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => FinanceBackground(child: child!),
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: Text('первая'));
          },
        ),
      ),
    );
    // The first page has only the app's backdrop.
    expect(find.byType(FinanceBackdropLayer), findsOneWidget);
    Navigator.of(ctx).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('вторая')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // Mid-way: the new page carries its own backdrop, and slides from the
    // side (its left edge is still to the right).
    expect(find.byType(FinanceBackdropLayer), findsNWidgets(2));
    expect(tester.getTopLeft(find.text('вторая')).dx, greaterThan(0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(Scaffold).last).dx, 0);
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();
    expect(find.text('вторая'), findsNothing);
    expect(find.byType(FinanceBackdropLayer), findsOneWidget);
  });

  test('виджеты: мини 1×1 и яркие фоны', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('.FinoraWidgetMini'));
    for (final c in ['violet', 'mint', 'blue', 'pink', 'red', 'teal']) {
      expect(
        File(
          'android/app/src/main/res/drawable/widget_vivid_$c.xml',
        ).existsSync(),
        isTrue,
      );
    }
    for (final layout in ['small', 'wide', 'payments', 'buddy', 'mini']) {
      expect(
        File(
          'android/app/src/main/res/layout/widget_$layout.xml',
        ).readAsStringSync(),
        contains('finora_mood_'),
        reason: layout,
      );
    }
    expect(WhatsNew.items.map((i) => i.$2), contains('Яркие виджеты'));
  });
}
