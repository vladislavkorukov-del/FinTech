import 'dart:io';

import 'package:finora/presentation/widgets/common.dart';
import 'package:finora/services/user_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('stream exception never shows signed CDN URL or giant snackbar', (
    tester,
  ) async {
    final error = HttpException(
      'Connection closed while receiving data',
      uri: Uri.parse(
        'https://us.aws.cdn.hf.co/xet-bridge-us/weights?Signature=PRIVATE_NONCE&token=SECRET',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showError(context, error),
              child: const Text('fail'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('fail'));
    await tester.pump();
    expect(
      find.text('Соединение прервалось. Можно повторить действие.'),
      findsOneWidget,
    );
    expect(find.textContaining('PRIVATE_NONCE'), findsNothing);
    expect(find.textContaining('HttpException'), findsNothing);
    expect(find.textContaining('xet-bridge'), findsNothing);
  });

  test(
    'functional errors survive, technical messages are bounded and redacted',
    () {
      expect(
        userErrorMessage(const FormatException('Укажите счёт')),
        'Укажите счёт',
      );
      final message = userErrorMessage(
        FormatException(
          'Ошибка https://cdn.example/x?token=TOP_SECRET ${'x' * 1000}',
        ),
      );
      expect(message, isNot(contains('TOP_SECRET')));
      expect(message.runes.length, lessThanOrEqualTo(240));
      expect(
        userErrorMessage(StateError('secret=INTERNAL')),
        isNot(contains('INTERNAL')),
      );
    },
  );
}
