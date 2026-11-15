import 'dart:ui';

import 'package:finora/domain/models.dart';
import 'package:finora/presentation/finora_assets.dart';
import 'package:finora/presentation/widgets/finora_orb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2.3: Finora's eyes and emotions are back, and can be turned off in
/// Settings — then she is a sphere of light.
void main() {
  tearDown(() => FinoraOrbPainter.plain = false);

  test('the setting is saved and is on by default', () {
    expect(const AppPreferences().finoraFace, isTrue);
    expect(AppPreferences.fromJson({}).finoraFace, isTrue);
    final off = const AppPreferences().copyWith(finoraFace: false);
    expect(AppPreferences.fromJson(off.toJson()).finoraFace, isFalse);
  });

  test('both looks paint in every mood', () {
    for (final plain in [false, true]) {
      FinoraOrbPainter.plain = plain;
      for (final m in FinoraMood.values) {
        final rec = PictureRecorder();
        FinoraOrbPainter(
          t: .3,
          mood: m,
          joy: .4,
        ).paint(Canvas(rec), const Size.square(120));
        expect(rec.endRecording(), isNotNull);
      }
    }
  });

  test('without emotions she does not hop, shake or bounce', () {
    expect(hopHeight(.2), greaterThan(0));
    FinoraOrbPainter.plain = true;
    expect(hopHeight(.2), 0);
    expect(wiggle(.3), 0);
    expect(bounce(.1), 1);
  });

  testWidgets('achievement cards: drawings with a face, or her sphere', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 300,
          height: 162,
          child: FinoraArt(name: 'first_step'),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    FinoraOrbPainter.plain = true;
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 301,
          height: 162,
          child: FinoraArt(name: 'first_step'),
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.byType(FinoraCharacter), findsOneWidget);
  });
}
