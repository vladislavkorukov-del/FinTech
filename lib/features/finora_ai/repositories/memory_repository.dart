import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../memory/personal_memory.dart';
import '../memory/assistant_preferences.dart';

/// Where Finora's personal memory lives: one JSON file next to the app's
/// database, apart from the ledger (backups and imports are not affected).
/// Without a file system (widget tests) it simply stays in memory.
class MemoryRepository {
  MemoryRepository({this.file});

  /// Fixed file (tests); otherwise the app support directory.
  final File? file;
  PersonalMemory? _memory;
  Future<void>? _loading;
  bool _loaded = false;
  Timer? _save;
  Future<void>? _writes;
  FormatException? _readError;
  FormatException? get readError => _readError;

  static const fileName = 'finora_ai_memory.json';

  PersonalMemory get memory => _memory ??= PersonalMemory();

  Future<File?> _file() async {
    if (file != null) return file;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<PersonalMemory> load() => _loaded
      ? Future.value(memory)
      : (_loading ??= _load()).then((_) => memory);

  Future<void> _load() async {
    try {
      final f = await _file();
      if (f != null && await f.exists()) {
        _memory = PersonalMemory.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // Keep the original file byte-for-byte. Learning can still use the
      // in-memory fallback, but cannot overwrite an unreadable memory file.
      _readError = const FormatException(
        'Персональная память не прочитана. Исходный файл сохранён; восстановите резервную копию или явно сбросьте персонализацию.',
      );
      _memory = PersonalMemory();
    } finally {
      _loaded = true;
    }
  }

  /// Saves soon (several changes in a row are written once).
  void saveSoon() {
    _save?.cancel();
    _save = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(save().catchError((Object _) {})),
    );
  }

  Future<void> _write(PersonalMemory snapshot) async {
    final f = await _file();
    if (f == null) return;
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> _enqueue(Future<void> Function() task) {
    final previous = _writes;
    final next = previous == null
        ? Future<void>.sync(task)
        : previous.catchError((Object _) {}).then((_) => task());
    _writes = next;
    void release() {
      if (identical(_writes, next)) _writes = null;
    }

    unawaited(
      next.then<void>(
        (_) => release(),
        onError: (Object _, StackTrace _) => release(),
      ),
    );
    return next;
  }

  void _checkReadable() {
    if (_readError != null) throw _readError!;
  }

  Future<void> save() async {
    await load();
    return _enqueue(() async {
      _checkReadable();
      await _write(memory);
    });
  }

  /// These methods are called only after explicit UI confirmation. Publish
  /// the new value in memory after its atomic file replacement succeeds.
  Future<void> setPreferences(AssistantPreferences value) async {
    await load();
    return _enqueue(() async {
      _checkReadable();
      final candidate = PersonalMemory.fromJson(memory.toJson())
        ..preferences = value;
      await _write(candidate);
      memory.preferences = value;
    });
  }

  Future<void> saveScenario(SavedAssistantScenario value) async {
    await load();
    return _enqueue(() async {
      _checkReadable();
      if (!memory.scenarios.any((s) => s.id == value.id) &&
          memory.scenarios.length >= 50) {
        throw const FormatException('Можно сохранить не больше 50 сценариев');
      }
      final candidate = PersonalMemory.fromJson(memory.toJson());
      candidate.scenarios.removeWhere((s) => s.id == value.id);
      candidate.scenarios.add(value);
      await _write(candidate);
      memory.scenarios.removeWhere((s) => s.id == value.id);
      memory.scenarios.add(value);
    });
  }

  Future<void> deleteScenario(String id) async {
    await load();
    return _enqueue(() async {
      _checkReadable();
      final candidate = PersonalMemory.fromJson(memory.toJson())
        ..scenarios.removeWhere((s) => s.id == id);
      await _write(candidate);
      memory.scenarios.removeWhere((s) => s.id == id);
    });
  }

  /// Replaces the memory (a backup restored; or an empty one — a reset)
  /// and writes it at once.
  Future<void> replace(PersonalMemory memory) async {
    await load();
    _save?.cancel();
    return _enqueue(() async {
      await _write(memory);
      _memory = memory;
      _readError = null;
    });
  }

  /// Forgets everything (used with «Сбросить все данные»).
  Future<void> clear() async {
    await load();
    _save?.cancel();
    return _enqueue(() async {
      final f = await _file();
      if (f != null && await f.exists()) await f.delete();
      _memory = PersonalMemory();
      _readError = null;
    });
  }

  void dispose() => _save?.cancel();
}
