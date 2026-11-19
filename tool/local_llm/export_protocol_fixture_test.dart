// Host-probe fixture generator, not an inference test. No user data.
// flutter test tool/local_llm/export_protocol_fixture_test.dart --no-pub
import 'dart:convert';
import 'dart:io';

import 'package:finora/features/finora_ai/actions/ai_actions.dart';
import 'package:finora/features/finora_ai/local_model/qwen_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export actual application prompt with synthetic context', () async {
    final fixture = <String, Object?>{
      'messages': [
        {
          'role': 'system',
          'content': QwenChat.instructions(AiActionSession.promptSchema),
        },
        {
          'role': 'user',
          'content': jsonEncode({
            'untrusted_current_objects': {
              'accounts': [
                {'id': 'cash', 'name': 'Наличные', 'currency': 'RUB'},
              ],
              'categories': [
                {'id': 'food', 'name': 'Продукты', 'kind': 'expense'},
              ],
            },
            'localDate': '2026-11-18T12:00:00+03:00',
            'timezoneOffsetMinutes': 180,
          }),
        },
        {'role': 'user', 'content': 'Привет! Как тебя зовут?'},
      ],
    };
    final path =
        Platform.environment['FINORA_QWEN_FIXTURE'] ??
        '/tmp/finora-qwen-protocol-fixture.json';
    await File(
      path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(fixture));
    expect((fixture['messages'] as List).length, 3);
  });
}
