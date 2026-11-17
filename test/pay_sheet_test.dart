import 'package:finora/presentation/widgets/success_burst.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The payment confirmation sheet: it rises, spins, checks and leaves on
/// its own — and still shows when the widget that started the payment has
/// been rebuilt away (a paid row moves to its next date).
void main() {
  testWidgets('shows after the starting row is gone, then leaves', (
    tester,
  ) async {
    final show = ValueNotifier(true);
    late OverlayState overlay;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (context, visible, _) => visible
                ? Builder(
                    builder: (context) {
                      overlay = SuccessBurst.overlayOf(context)!;
                      return const Text('row');
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    // The row disappears while the payment is being saved.
    show.value = false;
    await tester.pump();
    expect(find.text('row'), findsNothing);
    SuccessBurst.show(
      null,
      'Оплачено досрочно',
      subtitle: 'Ипотека −32 000 ₽',
      overlay: overlay,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('pay-sheet')), findsOneWidget);
    expect(find.text('Ипотека −32 000 ₽'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Оплачено досрочно'), findsOneWidget);
    // It never blocks touches and leaves by itself.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pay-sheet')), findsNothing);
  });
}
