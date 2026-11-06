import 'dart:ui' as ui;

import 'package:finora/domain/bank_catalog.dart';
import 'package:finora/domain/service_catalog.dart';
import 'package:finora/domain/store_catalog.dart';
import 'package:finora/presentation/widgets/service_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finance 1.12.1: a round logo is shown round and a square one square,
/// with no white square behind a round mark.
void main() {
  SubscriptionService store(String id) => ServiceCatalog.byId('store_$id')!;

  test('logos keep their own outline', () {
    for (final id in [
      'pyaterochka',
      'bristol',
      'vkusno_i_tochka',
      'dixy',
      'apteka_366',
      'megamarket',
    ]) {
      expect(store(id).shape, 'round', reason: id);
    }
    for (final id in ['magnit', 'whoosh', 'perekrestok', 'wildberries']) {
      expect(store(id).shape, 'square', reason: id);
    }
    expect(store('monetka').shape, 'tile'); // a pin keeps its light tile
    expect(BankCatalog.byRegNumber('1481')!.toService().shape, 'round');
    expect(BankCatalog.byRegNumber('1000')!.toService().shape, 'square');
    for (final s in [
      ...StoreCatalog.entries,
      ...BankCatalog.entries
          .where((b) => b.logoAsset != null)
          .map((b) => b.toService()),
    ]) {
      expect(['round', 'square', 'tile'], contains(s.shape), reason: s.id);
      if (s.shape == 'tile') continue;
      expect(s.inset, 0, reason: s.id);
      // Nothing behind round and square marks, except a white disc for a
      // see-through round mark (a ring) so it stays visible on dark themes.
      final alpha = s.background >> 24;
      expect(
        alpha == 0 || (s.shape == 'round' && s.background == 0xFFFFFFFF),
        isTrue,
        reason: s.id,
      );
    }
    expect(store('shokoladnitsa').background, 0xFFFFFFFF);
    expect(store('bristol').background >> 24, 0);
  });

  testWidgets('round copies are transparent outside the mark', (tester) async {
    final round = [
      ...StoreCatalog.entries,
      ...BankCatalog.entries.map((b) => b.toService()),
    ].where((s) => s.shape == 'round').toList();
    expect(round.length, greaterThan(20));
    for (final s in round) {
      await tester.runAsync(() async {
        final bytes = await rootBundle.load(s.renderAssetPath!);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final image = (await codec.getNextFrame()).image;
        final rgba = (await image.toByteData())!.buffer.asUint8List();
        int alphaAt(int x, int y) => rgba[(y * image.width + x) * 4 + 3];
        // The bottom-left corner of a round mark is empty (Пятёрочка's leaf
        // sits top-right, Сбер's tick top-right).
        expect(alphaAt(1, image.height - 2), lessThan(20), reason: s.id);
      });
    }
  });

  testWidgets('badge draws a circle without a tile for a round mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ServiceBadge(name: 'Пятёрочка 1234'),
              ServiceBadge(name: 'Магнит'),
            ],
          ),
        ),
      ),
    );
    Container badge(String id) => tester.widget<Container>(
      find.byKey(ValueKey('service-badge-store_$id')),
    );
    final round = badge('pyaterochka');
    final roundDecoration = round.decoration! as BoxDecoration;
    expect(roundDecoration.shape, BoxShape.circle);
    expect(roundDecoration.color!.a, 0);
    expect(round.clipBehavior, Clip.none);
    expect(round.foregroundDecoration, isNull);
    final square = badge('magnit');
    final squareDecoration = square.decoration! as BoxDecoration;
    expect(squareDecoration.shape, BoxShape.rectangle);
    expect(squareDecoration.color!.a, 0);
  });
}
