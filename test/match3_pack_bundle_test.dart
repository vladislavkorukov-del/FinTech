import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:finora/presentation/screens/world/flow_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'all 87 source records load original PNG bytes from the real bundle',
    (tester) async {
      final index =
          jsonDecode(
                File('docs/match3_pack/asset_index.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final records = (index['assets'] as List).cast<Map<String, dynamic>>();
      expect(records.length, 87);
      expect(FlowArt.ids.toSet(), records.map((a) => a['id']).toSet());
      final decoded = <String>{};
      await tester.runAsync(() async {
        for (final item in records) {
          final id = item['id'] as String;
          final path = FlowArt.path(id);
          expect(path, item['path']);
          final data = await rootBundle.load(path);
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          expect(sha256.convert(bytes).toString(), item['sha256'], reason: id);
          if (decoded.add(path)) {
            final codec = await ui.instantiateImageCodec(bytes);
            final frame = await codec.getNextFrame();
            expect(frame.image.width, item['width'], reason: id);
            expect(frame.image.height, item['height'], reason: id);
            frame.image.dispose();
            codec.dispose();
          }
          if (item['preserve_square'] == true && !id.startsWith('map_bg_')) {
            // Square game sprites keep their whole canvas (1024, or 1254
            // for the 1.62 drone).
            expect(
              FlowArt.bounds(id),
              Rect.fromLTWH(
                0,
                0,
                (item['width'] as num).toDouble(),
                (item['height'] as num).toDouble(),
              ),
            );
            expect(FlowArt.bounds(id, trim: false), FlowArt.bounds(id));
          }
        }
      });
      expect(decoded.length, 81);
      expect(
        FlowArt.path('map_star_earned'),
        FlowArt.path('victory_star_earned'),
      );
      expect(
        FlowArt.path('out_of_moves_button_primary_base'),
        FlowArt.path('victory_button_primary_base'),
      );
      expect(
        FlowArt.path('out_of_moves_goal_coin'),
        FlowArt.path('victory_reward_coin'),
      );
      final layout =
          jsonDecode(await rootBundle.loadString(FlowArt.mapLayoutAsset))
              as Map<String, dynamic>;
      expect(layout['reference_width'], 724);
      expect(layout['section_height'], 724);
      expect(layout['platform_anchors'], hasLength(13));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual PNG button has one action and accessible label at minimum 48dp',
    (tester) async {
      var presses = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FlowArtButton(
                key: const ValueKey('art-button'),
                art: 'pause_button_continue',
                label: 'Продолжить игру',
                onPressed: () => presses++,
                width: 40,
                height: 40,
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(FlowArtButton));
      await tester.runAsync(() => FlowArt.precacheVisible(context));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('art-button'))),
        const Size(48, 48),
      );
      expect(find.bySemanticsLabel('Продолжить игру'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Продолжить игру'))
            .getSemanticsData()
            .hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
      expect(find.text('Продолжить игру'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('art-button')));
      await tester.pump();
      expect(presses, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    },
  );

  testWidgets(
    'nine-slice keeps original top and bottom corners when only panel height changes',
    (tester) async {
      tester.view.physicalSize = const Size(600, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final height in [340.0, 580.0])
                  RepaintBoundary(
                    key: ValueKey('panel-$height'),
                    child: SizedBox(
                      width: 280,
                      height: height,
                      child: FlowArtPanel(
                        child: SizedBox(width: 240, height: height - 40),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(FlowArtPanel).first);
      await tester.runAsync(() => FlowArt.precacheVisible(context));
      await tester.pumpAndSettle();
      final pixels = <Uint8List>[];
      await tester.runAsync(() async {
        for (final h in [340.0, 580.0]) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(ValueKey('panel-$h')),
          );
          final image = await boundary.toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          pixels.add(
            data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          image.dispose();
        }
      });
      // Width and pixel density are identical. A stretched bitmap would alter
      // these border rows; a proper nine-slice retains the source corner geometry.
      const rowBytes = 280 * 4, borderBytes = rowBytes * 30;
      expect(
        pixels[0].sublist(0, borderBytes),
        pixels[1].sublist(0, borderBytes),
      );
      final shortBottom = pixels[0].sublist(pixels[0].length - borderBytes);
      final tallBottom = pixels[1].sublist(pixels[1].length - borderBytes);
      // Floating point translation at the lower edge can round a colour
      // channel by one. It must not change the silhouette or border geometry.
      var totalDifference = 0;
      for (var i = 0; i < shortBottom.length; i++) {
        final difference = (shortBottom[i] - tallBottom[i]).abs();
        expect(difference, lessThanOrEqualTo(2));
        totalDifference += difference;
      }
      expect(totalDifference / shortBottom.length, lessThan(.1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'lettering uses supplied cap and x-height rather than equal word widths',
    () {
      final score = FlowArt.info('victory_label_score');
      final reward = FlowArt.info('victory_label_reward');
      expect(
        FlowArt.labelHeight('victory_label_score', capitalHeight: 14) /
            score.bounds().height *
            score.capitalHeight!,
        closeTo(14, .0001),
      );
      expect(
        FlowArt.labelHeight('victory_label_reward', capitalHeight: 14) /
            reward.bounds().height *
            reward.capitalHeight!,
        closeTo(14, .0001),
      );
      final next = FlowArt.info('victory_label_next');
      expect(
        FlowArt.labelHeight('victory_label_next', xHeight: 16) /
            next.bounds().height *
            next.xHeight!,
        closeTo(16, .0001),
      );
      expect(
        FlowArt.bounds('obstacle_ice_intact'),
        FlowArt.bounds('obstacle_ice_cracked'),
      );
      expect(
        FlowArt.bounds('obstacle_chain_intact'),
        FlowArt.bounds('obstacle_chain_damaged'),
      );
      expect(
        FlowArt.bounds('obstacle_crate_intact'),
        FlowArt.bounds('obstacle_crate_damaged'),
      );
    },
  );
}
