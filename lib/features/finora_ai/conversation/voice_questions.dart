import '../../../domain/models.dart';
import '../insights/debt_advice.dart';
import '../insights/what_if.dart';
import '../reports/report_builder.dart';
import '../responses/intent_parser.dart';
import '../services/finora_ai.dart';

/// Questions asked to the voice assistant (Phase 6). The voice parser is
/// unchanged: only a phrase it did not recognize as a command comes here,
/// and when it is a question Finora AI knows («сколько я могу потратить?»,
/// «как мне погасить долги?»), the engines answer it with the same facts
/// as in the chat. Otherwise null — the voice says it did not understand.
abstract final class VoiceQuestions {
  /// The longest reply shown in Finora's bubble; the chat has the rest.
  static const maxLength = 260;

  static String? answer(String heard, FinanceData data, {DateTime? now}) {
    final text = heard.trim();
    if (text.isEmpty) return null;
    final known =
        IntentParser.parse(text).intent != AiIntent.unknown ||
        DebtAdvice.matches(text) ||
        ReportBuilder.parseRequest(text) != null ||
        WhatIf.matches(text);
    if (!known) return null;
    final ai = FinoraAi.instance;
    final reply = ai.answer(text, ai.snapshot(data, now: now)).text.trim();
    if (reply.isEmpty) return null;
    return shorten(reply);
  }

  /// The first lines of [reply] that fit [maxLength].
  static String shorten(String reply) {
    if (reply.length <= maxLength) return reply;
    final out = StringBuffer();
    for (final line in reply.split('\n')) {
      if (out.length + line.length + 1 > maxLength) break;
      if (out.isNotEmpty) out.write('\n');
      out.write(line);
    }
    if (out.isEmpty) return '${reply.substring(0, maxLength - 1)}…';
    return '$out\nПодробнее — в Finora AI.';
  }
}
