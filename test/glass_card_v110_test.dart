import 'dart:ui' as ui;

import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}

/// Finance 1.10: «liquid glass» cards. Text stays readable on the glass over
/// any part of the backdrop, and the card corners show no square of shadow.
void main() {
  for (final preset in AppTheme.presetNames.keys) {
    for (final b in Brightness.values) {
      test('$preset ${b.name}: text readable on glass', () {
        final theme = AppTheme.app(b, preset);
        final backdrop = theme.extension<FinanceBackdrop>()!;
        final ink = theme.colorScheme.onSurface;
        final fill = GlassSurface.fill(theme, null, null, 1);
        for (final under in [backdrop.top, backdrop.middle, backdrop.bottom]) {
          for (final f in fill) {
            final seen = Color.alphaBlend(f, under);
            expect(_contrast(ink, seen), greaterThanOrEqualTo(4.5));
          }
        }
        // Glass is translucent: the backdrop reads through.
        expect(fill.every((c) => c.a < 1), isTrue);
      });
    }
  }

  testWidgets('corners outside the rounded card are never lightened', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const backdrop = Color(0xFF202838);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.app(Brightness.dark, 'midnight'),
        home: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: backdrop,
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: SurfaceCard(
                onTap: () {},
                child: const SizedBox(height: 60),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byType(GlassSurface));
    final bytes = await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    Color at(Offset p) {
      final i = (p.dy.round() * 240 + p.dx.round()) * 4;
      return Color.fromARGB(
        255,
        bytes!.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
    }

    final base = backdrop.computeLuminance();
    // Just inside each bounding-box corner but outside the 24 px radius.
    for (final p in [
      card.topLeft + const Offset(2, 2),
      card.topRight + const Offset(-3, 2),
      card.bottomLeft + const Offset(2, -3),
      card.bottomRight + const Offset(-3, -3),
      // Below the card, where the shadow falls.
      card.bottomLeft + const Offset(4, 6),
      card.bottomRight + const Offset(-4, 6),
    ]) {
      expect(
        at(p).computeLuminance(),
        lessThanOrEqualTo(base + .002),
        reason: 'corner at $p must not show a light square',
      );
    }
    // The glass body itself is lighter than the backdrop (shadow is not
    // painted under it).
    expect(at(card.center).computeLuminance(), greaterThan(base));
    expect(
      at(card.bottomCenter - const Offset(0, 6)).computeLuminance(),
      greaterThan(base),
    );
  });
}
