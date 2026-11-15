import 'dart:io';

import 'package:finora/domain/achievements.dart';
import 'package:finora/presentation/finora_assets.dart';
import 'package:finora/presentation/whats_new.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('2.2: achievement cards draw Finora, no illustrations with a face', () {
    for (final d in achievementDefinitions) {
      expect(FinoraAssets.achievementArt(d), isNull);
    }
    expect(Directory('assets/finora/achievements').existsSync(), isFalse);
    expect(FinoraAssets.cardRatio, closeTo(1706 / 922, .01));
  });

  test('«Что нового» 1.45 — карточки на весь экран', () {
    final titles = WhatsNew.items.map((i) => i.$2);
    expect(titles, contains('Достижение — на весь экран'));
  });
}
