import 'package:finora/domain/amount_expression.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/presentation/widgets/amount_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The calculator in the amount pad: whole kopecks, operator precedence,
/// percentages, a live result in the field.
void main() {
  test('expressions are evaluated in kopecks', () {
    expect(AmountExpression.evaluate('450+120'), 57000);
    expect(AmountExpression.evaluate('1 200×3'), 360000);
    expect(AmountExpression.evaluate('100+2×3'), 10600);
    expect(AmountExpression.evaluate('10÷3'), 333);
    expect(AmountExpression.evaluate('20÷3'), 667);
    expect(AmountExpression.evaluate('99,99+0,01'), 10000);
    expect(AmountExpression.evaluate('3000−15%'), 255000);
    expect(AmountExpression.evaluate('3000+10%'), 330000);
    expect(AmountExpression.evaluate('100×2+10%'), 22000);
    expect(AmountExpression.evaluate('2000×15%'), 30000);
    expect(AmountExpression.evaluate('50-70'), -2000);
    expect(AmountExpression.evaluate('450+'), 45000);
    expect(AmountExpression.evaluate('5÷0'), isNull);
    expect(AmountExpression.evaluate('5++5'), isNull);
    expect(AmountExpression.evaluate('1,234'), isNull);
    expect(AmountExpression.evaluate(''), isNull);
    expect(AmountExpression.isCalculation('1 200,50'), isFalse);
    expect(AmountExpression.isCalculation('1200+5'), isTrue);
    expect(AmountExpression.pretty('1200+35,5'), '1 200 + 35,5');
  });

  testWidgets('the pad calculates and the field holds the result', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AmountPad(controller: controller)),
      ),
    );
    Future<void> press(List<String> keys) async {
      for (final k in keys) {
        await tester.tap(find.text(k));
        await tester.pump();
      }
    }

    await press(['4', '5', '0', '+', '1', '2', '0']);
    expect(FinanceEngine.parseMinor(controller.text), 57000);
    expect(find.byKey(const ValueKey('amount-expression')), findsOneWidget);
    await press(['×', '2']);
    // × binds tighter: 450 + 240.
    expect(FinanceEngine.parseMinor(controller.text), 69000);
    await press(['=']);
    expect(controller.text, '690');
    expect(find.byKey(const ValueKey('amount-expression')), findsNothing);
    // Someone else (voice) fills the field: the pad starts from it.
    controller.text = '1 000';
    await tester.pump();
    await press(['−', '1', '0', '%']);
    expect(FinanceEngine.parseMinor(controller.text), 90000);
    await press(['C']);
    expect(controller.text, '');
  });
}
