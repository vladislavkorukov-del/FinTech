import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/style_ids.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Finance 1.9: 14 themes from the owner's references. Every style shown in
/// Settings must be accepted by the repository (an earlier version lost new
/// styles because the repository whitelist lagged behind the UI).
void main() {
  sqfliteFfiInit();
  test('settings styles and repository ids are the same list', () {
    expect(AppTheme.presetNames.keys.toList(), visualStyleIds);
    // Release: the palettes are gone; their ids stay valid and open in the
    // one style.
    for (final id in releaseRemovedStyleIds) {
      expect(legacyStyleIds, contains(id));
      expect(AppTheme.styleOf(id), 'coffee');
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
      // 1.55: removed styles still load from older settings and are drawn
      // in Coffee.
      for (final id in removedStyleIds) {
        data = data.copyWith(
          preferences: data.preferences.copyWith(accent: id),
        );
        await repository.save(data);
        expect((await repository.load()).preferences.accent, id);
        expect(AppTheme.styleOf(id), 'coffee');
        expect(AppTheme.presetNames, isNot(contains(id)));
      }
    } finally {
      await repository.close();
      await directory.delete(recursive: true);
    }
  });
}
