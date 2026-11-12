import 'package:finora/presentation/screens/world/flow_hud.dart';
import 'package:finora/presentation/screens/world/flow_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'score fill clips a full-width sprite and stars use actual thresholds',
    (tester) async {
      for (final score in [0, 100, 200, 400, 999]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 240,
                  height: 34,
                  child: FlowScoreTrack(
                    score: score,
                    thresholds: const [100, 200, 400],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final fill = find.byKey(const ValueKey('flow-score-fill'));
        final size = tester.getSize(fill);
        final clip = tester.widget<ClipRect>(fill).clipper!.getClip(size);
        expect(
          clip.width,
          closeTo(size.width * (score / 400).clamp(0, 1), .001),
        );
        expect(
          tester
              .getSize(
                find.descendant(of: fill, matching: find.byType(FlowSprite)),
              )
              .width,
          size.width,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is FlowSprite && w.id == 'hud_star_active',
          ),
          findsNWidgets(
            [100, 200, 400].where((threshold) => score >= threshold).length,
          ),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
