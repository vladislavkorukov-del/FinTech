import 'dart:convert';

/// Protocol is deliberately not an instruction execution language. Only a
/// complete, validated envelope can reach the separate action registry.
class ModelEnvelope {
  const ModelEnvelope(this.kind, this.data);
  final String kind;
  final Map<String, dynamic> data;

  static ModelEnvelope parse(String raw) {
    final clean = visibleModelText(raw, complete: true).trim();
    final decoded = jsonDecode(clean);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Ожидался объект ответа.');
    }
    final kind = decoded['kind'];
    final keys = switch (kind) {
      'reply' => {'kind', 'text'},
      'fact' => {'kind', 'intent'},
      'action' => {'kind', 'action', 'args'},
      _ => throw const FormatException('Неизвестный тип ответа.'),
    };
    if (decoded.keys.any((k) => !keys.contains(k)) ||
        decoded.length != keys.length) {
      throw const FormatException('Некорректная структура ответа.');
    }
    if (kind == 'reply' && decoded['text'] is! String ||
        kind == 'fact' && decoded['intent'] is! String ||
        kind == 'action' &&
            (decoded['action'] is! String ||
                decoded['args'] is! Map<String, dynamic>)) {
      throw const FormatException('Некорректные поля ответа.');
    }
    return ModelEnvelope(kind as String, decoded);
  }
}

/// Suppress reasoning, including incomplete tags split across stream chunks.
/// An unclosed reasoning block is never returned as visible text.
String visibleModelText(String raw, {bool complete = false}) {
  var rest = raw;
  final visible = StringBuffer();
  while (rest.isNotEmpty) {
    final start = rest.indexOf('<think>');
    if (start < 0) {
      if (rest.contains('</think>')) {
        // Some runtimes prefill an opening think tag. Nothing before its
        // closing tag may be exposed either.
        rest = rest.substring(rest.indexOf('</think>') + 8);
        continue;
      }
      var end = rest.length;
      for (var n = 1; n < '<think>'.length && n <= rest.length; n++) {
        if (rest.endsWith('<think>'.substring(0, n))) end = rest.length - n;
      }
      visible.write(rest.substring(0, end));
      break;
    }
    visible.write(rest.substring(0, start));
    final end = rest.indexOf('</think>', start + 7);
    if (end < 0) break;
    rest = rest.substring(end + 8);
  }
  return visible
      .toString()
      .replaceAll('<|im_end|>', '')
      .replaceAll('<|endoftext|>', '');
}

/// Extract only a JSON reply's text string while it streams. Never display
/// JSON, function arguments or reasoning. Final schema validation is separate.
String streamedReply(String raw) {
  final text = visibleModelText(raw);
  if (!RegExp(
    r'^\s*\{\s*"kind"\s*:\s*"reply"\s*,\s*"text"\s*:\s*"',
  ).hasMatch(text)) {
    return '';
  }
  final prefix = RegExp(
    r'^\s*\{\s*"kind"\s*:\s*"reply"\s*,\s*"text"\s*:\s*"',
  ).firstMatch(text)!;
  final value = StringBuffer();
  var escaped = false;
  for (final code in text.substring(prefix.end).runes) {
    if (escaped) {
      // Incomplete escapes are withheld; unicode escapes need the final
      // decoder (not exposing them is preferable to corrupting the display).
      if (code == 117) {
        return safeSmallTalk(value.toString()) ? value.toString() : '';
      }
      value.write(switch (code) {
        110 => '\n',
        114 => '\r',
        116 => '\t',
        _ => String.fromCharCode(code),
      });
      escaped = false;
    } else if (code == 92) {
      escaped = true;
    } else if (code == 34) {
      break;
    } else {
      value.writeCharCode(code);
    }
  }
  return safeSmallTalk(value.toString()) ? value.toString() : '';
}

/// Financial facts and claims of completed changes are rendered by app code,
/// never by the language model. This conservative guard complements routing;
/// it is not represented as a general factuality verifier.
bool safeSmallTalk(String text) => !RegExp(
  r'[0-9₽$€¥]|добавил|удалил|изменил|сохранил|перев[её]л|списал|'
  r'ваш[аи]? (баланс|расход|доход|плат[её]ж)|тво[йияё] (баланс|расход|доход)|'
  r'баланс|сч[её]т|кредит|ипотек|плат[её]ж|подписк|операци[яиюе]|доход|расход|'
  r'готово|выполн|провед[её]н|записан|создан|оплач|сохран[её]н|обновл[её]н|измен[её]н|удал[её]н|цель достиг|'
  r'у (тебя|вас)|вы потратили|ты потратил|'
  r'<think|</think|<\|',
  caseSensitive: false,
).hasMatch(text);
