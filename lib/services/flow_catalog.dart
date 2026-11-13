import 'package:flutter/services.dart';

import '../domain/flow/flow.dart';

/// Local level definitions are loaded once, independently of finances/network.
abstract final class FlowCatalog {
  static Future<List<FlowLevel>>? _pending;

  static Future<List<FlowLevel>> load() => _pending ??= _load();

  static Future<List<FlowLevel>> _load() async {
    try {
      // 1.62: the twenty hand-made levels, then 21–500 from the generator.
      final made = FlowLevels.decode(
        await rootBundle.loadString('assets/flow/levels.json'),
      );
      return List.unmodifiable([...made, ...FlowLevelGenerator.all()]);
    } catch (_) {
      _pending = null;
      rethrow;
    }
  }
}
