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

/// Finance 1.10: «liquid glass» cards. Text stays readable on the glass and on
/// the backdrop over its brightest orbs, and the card corners show nothing
/// but the backdrop (no square of shadow).
void main() {
  for (final preset in AppTheme.presetNames.keys) {
    for (final b in Brightness.values) {
      test('$preset ${b.name}: text readable on glass and backdrop', () {
        final theme = AppTheme.app(b, preset);
        final backdrop = theme.extension<FinanceBackdrop>()!;
        final ink = theme.colorScheme.onSurface;
        final secondary = theme.colorScheme.onSurfaceVariant;
        final pane = GlassSurface.pane(theme, null, null, 1);
        // 1.0.0+119: liquid glass again — translucent, yet readable.
        expect(pane.a, inInclusiveRange(.6, .85));
        for (final under in [backdrop.top, backdrop.middle, backdrop.bottom]) {
          // The brightest spot is right under a color orb.
          for (final orb in [
            Colors.transparent,
            backdrop.glowA,
            backdrop.glowB,
          ]) {
            final bare = Color.alphaBlend(orb, under);
            expect(_contrast(ink, bare), greaterThanOrEqualTo(4.5));
            final seen = Color.alphaBlend(pane, bare);
            expect(_contrast(ink, seen), greaterThanOrEqualTo(4.5));
            expect(_contrast(secondary, seen), greaterThanOrEqualTo(4.5));
          }
        }
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

    // Just inside each bounding-box corner but outside the 24 px radius,
    // and below the card: never lighter than the backdrop (no square of
    // haze); the soft glass shadow may only darken it a little.
    for (final p in [
      card.topLeft + const Offset(2, 2),
      card.topRight + const Offset(-3, 2),
      card.bottomLeft + const Offset(2, -3),
      card.bottomRight + const Offset(-3, -3),
      card.bottomLeft + const Offset(4, 6),
      card.bottomRight + const Offset(-4, 6),
    ]) {
      final c = at(p);
      expect(
        [
          c.r - backdrop.r,
          c.g - backdrop.g,
          c.b - backdrop.b,
        ].every((d) => d < 2 / 255 && d > -24 / 255),
        isTrue,
        reason: 'corner at $p must not be lightened, got $c',
      );
    }
    // The card is drawn, and its edge is one visible hairline (the glass
    // rim catches the light, so it differs from the body).
    expect(at(card.center), isNot(backdrop));
    expect(at(card.topCenter), isNot(at(card.center))); // the 1 px edge row
  });
}
