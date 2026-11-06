import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/style_ids.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/theme/reference_palettes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Finance 1.9: 14 themes from the owner's references. Every style shown in
/// Settings must be accepted by the repository (an earlier version lost new
/// styles because the repository whitelist lagged behind the UI).
void main() {
  sqfliteFfiInit();
  test('settings styles and repository ids are the same list', () {
    expect(AppTheme.presetNames.keys.toList(), visualStyleIds);
    for (final id in [
      'sunset',
      'rose',
      'neon',
      'crimson',
      'dusk',
      'emerald',
      'tropic',
      'twilight',
      'plum',
      'wine',
      'copper',
      'sand',
      'apricot',
      'terracotta',
    ]) {
      expect(referencePalettes, contains(id));
      expect(AppTheme.accent(id), referencePalettes[id]!.accent);
    }
  });

  test('every style survives save and reload', () async {
    final directory = await Directory.systemTemp.createTemp('finance-styles-');
    final repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/db',
    );
    try {
      var data = await repository.load();
      for (final id in visualStyleIds) {
        data = data.copyWith(
          preferences: data.preferences.copyWith(accent: id),
        );
        await repository.save(data);
        expect((await repository.load()).preferences.accent, id);
      }
    } finally {
      await repository.close();
      await directory.delete(recursive: true);
    }
  });
}
