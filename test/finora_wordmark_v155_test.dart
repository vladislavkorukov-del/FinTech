import 'package:finora/presentation/widgets/finora_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1.55: the launch screen writes «Finora» letter by letter, then rests.
void main() {
  testWidgets('the wordmark plays once and rests on the whole word', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: FinoraWordmark()))),
    );
    expect(find.bySemanticsLabel('Finora'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    for (final letter in FinoraWordmark.word.split('')) {
      expect(find.text(letter), findsWidgets);
    }
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('with reduced motion the word is shown at once', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Center(child: FinoraWordmark())),
        ),
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(ImageFiltered), findsNothing);
  });
}
