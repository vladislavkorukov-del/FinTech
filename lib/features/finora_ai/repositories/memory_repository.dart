import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../memory/personal_memory.dart';

/// Where Finora's personal memory lives: one JSON file next to the app's
/// database, apart from the ledger (backups and imports are not affected).
/// Without a file system (widget tests) it simply stays in memory.
class MemoryRepository {
  MemoryRepository({this.file});

  /// Fixed file (tests); otherwise the app support directory.
  final File? file;
  PersonalMemory? _memory;
  Future<void>? _loading;
  Timer? _save;

  static const fileName = 'finora_ai_memory.json';

  PersonalMemory get memory => _memory ??= PersonalMemory();

  Future<File?> _file() async {
    if (file != null) return file;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$fileName');
    } catch (_) {
      return null;
    }
  }

  Future<PersonalMemory> load() => (_loading ??= _load()).then((_) => memory);

  Future<void> _load() async {
    try {
      final f = await _file();
      if (f != null && await f.exists()) {
        _memory = PersonalMemory.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // A damaged file starts a fresh memory; the ledger is untouched.
      _memory = PersonalMemory();
    }
  }

  /// Saves soon (several changes in a row are written once).
  void saveSoon() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 400), () => unawaited(save()));
  }

  Future<void> save() async {
    final f = await _file();
    if (f == null) return;
    try {
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(memory.toJson()));
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// Replaces the memory (a backup restored; or an empty one — a reset)
  /// and writes it at once.
  Future<void> replace(PersonalMemory memory) async {
    await load();
    _memory = memory;
    _save?.cancel();
    await save();
  }

  /// Forgets everything (used with «Сбросить все данные»).
  Future<void> clear() async {
    _memory = PersonalMemory();
    final f = await _file();
    if (f != null && await f.exists()) await f.delete();
  }
}
