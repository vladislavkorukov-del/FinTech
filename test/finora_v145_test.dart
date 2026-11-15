import 'dart:io';

import 'package:finora/domain/achievements.dart';
import 'package:finora/presentation/finora_assets.dart';
import 'package:finora/presentation/whats_new.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('у каждого достижения своя карточка в высоком качестве', () {
    expect(FinoraAssets.art.length, achievementDefinitions.length);
    for (final d in achievementDefinitions) {
      expect(FinoraAssets.achievementArt(d), d.id);
      final file = File(FinoraAssets.path(d.id));
      expect(file.existsSync(), isTrue, reason: d.id);
      final bytes = file.readAsBytesSync();
      // RIFF….WEBPVP8 and a 1024-pixel-wide picture.
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP');
      expect(bytes.length, greaterThan(20000), reason: d.id);
    }
    for (final name in FinoraAssets.reactionArt.values) {
      expect(FinoraAssets.art, contains(name));
    }
    expect(FinoraAssets.cardRatio, closeTo(1706 / 922, .01));
  });

  test('«Что нового» 1.45 — карточки на весь экран', () {
    final titles = WhatsNew.items.map((i) => i.$2);
    expect(titles, contains('Новые карточки достижений'));
    expect(titles, contains('Достижение — на весь экран'));
  });
}
