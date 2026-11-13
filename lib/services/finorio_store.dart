import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/finorio/finorio.dart';

/// Finorio's save file, kept apart from the ledger database: a broken or
/// missing game save can never touch financial data.
///
/// Writing is crash-safe: the new state goes to a temporary file first,
/// the current save is kept as a backup, then the temporary file takes its
/// place with an atomic rename. Loading falls back to the backup.
class FinorioStore {
  FinorioStore({Directory? root}) : _root = root;
  final Directory? _root;

  /// Tests point the default store at a temporary folder.
  static Directory? debugRoot;

  Future<Directory> _dir() async {
    final base = _root ?? debugRoot ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/finorio');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file(String name) async => File('${(await _dir()).path}/$name');

  /// The saved factory, or null when there is none (or none readable).
  Future<FinWorld?> load() async {
    for (final name in ['world.json', 'world.json.bak']) {
      final File file;
      try {
        file = await _file(name);
      } on Object {
        return null; // no storage: a new factory, saving will report it
      }
      if (!file.existsSync()) continue;
      try {
        final json = jsonDecode(await file.readAsString());
        return finWorldFromJson(Map<String, dynamic>.from(json as Map));
      } on Object {
        continue; // try the backup
      }
    }
    return null;
  }

  Future<void> save(FinWorld world) async {
    final main = await _file('world.json');
    final temp = await _file('world.json.tmp');
    final backup = await _file('world.json.bak');
    await temp.writeAsString(jsonEncode(world.toJson()), flush: true);
    if (main.existsSync()) await main.rename(backup.path);
    await temp.rename(main.path);
  }

  Future<void> clear() async {
    for (final name in ['world.json', 'world.json.bak', 'world.json.tmp']) {
      final f = await _file(name);
      if (f.existsSync()) await f.delete();
    }
  }
}
