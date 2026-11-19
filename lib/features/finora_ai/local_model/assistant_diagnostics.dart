import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../../services/user_error.dart';

/// Metadata only by default. Opt-in text contains visible messages, never
/// native raw output or hidden reasoning. Bounded, local and user-exported.
class AssistantDiagnostics extends ChangeNotifier {
  AssistantDiagnostics();
  static final instance = AssistantDiagnostics();
  bool collectText = false;
  final List<Map<String, Object?>> records = [];

  void record(
    String event, {
    Map<String, Object?> values = const {},
    String? visibleText,
  }) {
    records.add({
      'at': DateTime.now().toIso8601String(),
      'event': event,
      ...Map<String, Object?>.from(_redact(values) as Map),
      if (collectText && visibleText != null)
        'visibleText': redactDiagnosticText(visibleText),
    });
    if (records.length > 100) records.removeAt(0);
    notifyListeners();
  }

  static Object? _redact(Object? value) => switch (value) {
    String s => redactDiagnosticText(s),
    Map m => {for (final e in m.entries) '${e.key}': _redact(e.value)},
    List l => [for (final v in l) _redact(v)],
    _ => value,
  };

  void setCollectText(bool value) {
    collectText = value;
    if (!value) {
      for (final r in records) {
        r.remove('visibleText');
      }
    }
    notifyListeners();
  }

  void clear() {
    records.clear();
    notifyListeners();
  }

  Future<File> export({
    required Map<String, Object?> metadata,
    required Map<String, Object?> runtime,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/finora-local-ai-diagnostics.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'textCollection': collectText,
        'model': metadata,
        'runtime': runtime,
        'events': records,
      }),
      flush: true,
    );
    return file;
  }
}

/// Three distinct presses, each >=1.5s, released within the same 12s window.
/// Pointer-down/up rather than onLongPress avoids one hold counting thrice.
class DeveloperUnlock {
  DateTime? _start, _down;
  int _count = 0;
  void down(DateTime now) {
    if (_down != null) return;
    if (_start == null ||
        now.difference(_start!) > const Duration(seconds: 12)) {
      _start = now;
      _count = 0;
    }
    _down = now;
  }

  bool up(DateTime now) {
    final down = _down;
    _down = null;
    if (down == null) return false;
    if (now.difference(_start!) > const Duration(seconds: 12) ||
        now.difference(down) < const Duration(milliseconds: 1500)) {
      _start = null;
      _count = 0;
      return false;
    }
    _count++;
    if (_count < 3) return false;
    _start = null;
    _count = 0;
    return true;
  }

  void cancel() {
    _start = null;
    _down = null;
    _count = 0;
  }
}
