import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Existing chat remains the single UI; its visible messages now survive
/// recreation. No raw model output, tool JSON or reasoning is stored.
class AssistantHistory {
  AssistantHistory({this.file});
  final File? file;
  Future<void> _writes = Future.value();
  static const limit = 100;
  Map<String, dynamic>? session;

  Future<File?> _file() async {
    if (file != null) return file;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/finora_ai_chat.json');
  }

  Future<List<(String, bool)>> load() async {
    final f = await _file();
    if (f == null || !await f.exists()) return [];
    final json = jsonDecode(await f.readAsString());
    if (json is! Map || json['version'] != 1 || json['messages'] is! List) {
      throw const FormatException(
        'Не удалось прочитать историю чата. Файл сохранён.',
      );
    }
    session = json['session'] is Map
        ? Map<String, dynamic>.from(json['session'] as Map)
        : null;
    final messages = <(String, bool)>[];
    for (final m in json['messages'] as List) {
      if (m is! Map || m['text'] is! String || m['mine'] is! bool) {
        throw const FormatException('История чата повреждена. Файл сохранён.');
      }
      messages.add((m['text'] as String, m['mine'] as bool));
    }
    return messages
        .skip((messages.length - limit).clamp(0, messages.length))
        .toList();
  }

  Future<void> save(
    List<(String, bool)> messages, {
    Map<String, dynamic>? session,
  }) {
    final kept = messages.skip(
      (messages.length - limit).clamp(0, messages.length),
    );
    final encoded = jsonEncode({
      'version': 1,
      'session': ?session,
      'messages': [
        for (final m in kept) {'text': m.$1, 'mine': m.$2},
      ],
    });
    final next = _writes.catchError((Object _) {}).then((_) async {
      final f = await _file();
      if (f == null) return;
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(encoded, flush: true);
      await tmp.rename(f.path);
    });
    _writes = next;
    return next;
  }
}
