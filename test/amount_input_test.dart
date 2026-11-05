import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finora/domain/finance_engine.dart';
import 'package:finora/presentation/widgets/amount_pad.dart';
import 'package:finora/presentation/widgets/common.dart';

void main() {
  tearDown(() => FinanceFormat.numberPattern = 'space_comma');
  test('money formatting preserves cents at the maximum supported amount', () {
    FinanceFormat.numberPattern = 'comma_dot';
    expect(decimalMinor(9007199254740991), '90071992547409.91');
    expect(money(9007199254740991, 'USD'), '90,071,992,547,409.91 \$');
    expect(money(-123456, 'USD'), '−1,234.56 \$');
    expect(money(100, 'RUB'), '1 ₽');
    expect(
      FinanceEngine.parseMinor(decimalMinor(9007199254740991)),
      9007199254740991,
    );
  });
  testWidgets('numeric pad enters amount and prevents a third decimal place', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AmountPad(controller: controller)),
      ),
    );
    for (final key in ['1', '2', '3', ',', '4', '5', '6']) {
      await tester.tap(find.text(key));
      await tester.pumpAndSettle();
    }
    expect(controller.text, '123,45');
    expect(FinanceEngine.parseMinor(controller.text), 12345);
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pumpAndSettle();
    expect(controller.text, '123,4');
  });
}
