import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finora/domain/wardrobe.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/finora_dressed.dart';
import 'package:finora/presentation/widgets/finora_orb.dart';
import 'package:finora/presentation/widgets/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cape canvas and body geometry match the supplied placement at every scale',
    () {
      final metadata =
          jsonDecode(
                File(
                  'assets/finora/wardrobe_pack/cape_placement.json',
                ).readAsStringSync(),
              )
              as Map;
      expect(FinoraOutfitGeometry.sourceCanvas, const Size(1536, 1024));
      expect(
        FinoraOutfitGeometry.sourceBody,
        const Rect.fromLTWH(390, 130, 756, 756),
      );
      expect(metadata['canvas'], {'width': 1536, 'height': 1024});
      expect(metadata['finora_body_rect_on_canvas'], {
        'x': 390,
        'y': 130,
        'width': 756,
        'height': 756,
      });
      for (final d in [60.0, 100.0, 130.0, 200.0]) {
        final g = FinoraOutfitGeometry(d);
        final k = d / 756;
        expect(g.capeRect.width, closeTo(1536 * k, .00001));
        expect(g.capeRect.height, closeTo(1024 * k, .00001));
        expect(g.bodyRect.left - g.capeRect.left, closeTo(390 * k, .00001));
        expect(g.bodyRect.top - g.capeRect.top, closeTo(130 * k, .00001));
        expect(g.bodyRect.width, d);
        expect((Offset.zero & g.size).contains(g.capeRect.topLeft), isTrue);
        expect((Offset.zero & g.size).contains(g.capeRect.bottomRight), isTrue);
      }
    },
  );

  test(
    'all new companions keep visible size, side, image ratio and face separation',
    () async {
      final metadata =
          jsonDecode(
                File(
                  'assets/finora/wardrobe_pack/companions.json',
                ).readAsStringSync(),
              )
              as List;
      for (final entry in metadata) {
        final item = Wardrobe.item(entry['id'] as String)!;
        final g = const FinoraOutfitGeometry(100);
        final pet = g.companionRect(item);
        final bytes = await File(item.asset).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final sourceWidth = frame.image.width;
        final sourceHeight = frame.image.height;
        final rgba = (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        var left = sourceWidth, top = sourceHeight, right = -1, bottom = -1;
        for (var y = 0; y < sourceHeight; y++) {
          for (var x = 0; x < sourceWidth; x++) {
            if (rgba[(y * sourceWidth + x) * 4 + 3] >= 64) {
              if (x < left) left = x;
              if (y < top) top = y;
              if (x > right) right = x;
              if (y > bottom) bottom = y;
            }
          }
        }
        final visible = Rect.fromLTRB(
          pet.left + left / sourceWidth * pet.width,
          pet.top + top / sourceHeight * pet.height,
          pet.left + (right + 1) / sourceWidth * pet.width,
          pet.top + (bottom + 1) / sourceHeight * pet.height,
        );
        expect(
          visible.longestSide,
          inInclusiveRange(35, 45),
          reason: '${item.id} visible body',
        );
        if (item.fit.anchorY == 1) {
          expect(
            visible.bottom,
            closeTo(g.bodyRect.bottom, 1.0),
            reason: '${item.id} feet',
          );
        }
        frame.image.dispose();
        codec.dispose();
        expect(
          pet.width / pet.height,
          closeTo((entry['width'] as num) / (entry['height'] as num), .000001),
        );
        expect(
          pet.center.dx < g.bodyRect.center.dx,
          entry['side_default'] == 'left',
        );
        expect(
          visible.overlaps(
            Rect.fromCenter(center: g.bodyRect.center, width: 65, height: 65),
          ),
          isFalse,
          reason: '${item.id} covers face',
        );
        expect((Offset.zero & g.size).contains(pet.topLeft), isTrue);
        expect((Offset.zero & g.size).contains(pet.bottomRight), isTrue);
      }
      final koi = Wardrobe.item('pearl_koi')!;
      expect(koi.ratio, 1.5);
    },
  );

  test('motion-safe box contains full cape throughout hop, turn and drift', () {
    final g = const FinoraOutfitGeometry(100);
    for (var hop = 0; hop <= 100; hop++) {
      final h = hop / 100;
      for (final drift in [-3.0, 0.0, 3.0]) {
        final c = g.bodyRect.center;
        final matrix = Matrix4.identity()
          ..translateByDouble(c.dx, c.dy + drift - hopHeight(h) * 16, 0, 1)
          ..rotateZ(wiggle(h) * .14)
          ..scaleByDouble(bounce(h), bounce(h), 1, 1)
          ..translateByDouble(-c.dx, -c.dy, 0, 1);
        final bounds = MatrixUtils.transformRect(matrix, g.capeRect);
        final frame = (Offset.zero & g.size).inflate(.001);
        expect(
          frame.contains(bounds.topLeft),
          isTrue,
          reason: 'hop=$h drift=$drift $bounds',
        );
        expect(
          frame.contains(bounds.bottomRight),
          isTrue,
          reason: 'hop=$h drift=$drift $bounds',
        );
      }
    }
  });

  Future<ByteData> capture(WidgetTester tester, GlobalKey key) async {
    await tester.pump();
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = (await tester.runAsync(
      () => boundary.toImage(pixelRatio: 2),
    ))!;
    final data = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    image.dispose();
    return data;
  }

  testWidgets(
    'cape hole stays transparent and has an antialiased edge, no opaque plate',
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: const ClipPath(
                clipBehavior: Clip.antiAlias,
                clipper: CapeOutsideBodyClipper(
                  bodyRect: Rect.fromLTWH(24.7, 24.7, 50.6, 50.6),
                ),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: ColoredBox(color: Colors.red),
                ),
              ),
            ),
          ),
        ),
      );
      final data = (await capture(tester, key)).buffer.asUint8List();
      int alpha(int x, int y) => data[(y * 200 + x) * 4 + 3];
      expect(alpha(100, 100), 0);
      expect(alpha(100, 70), 0);
      expect(alpha(100, 155), 255);
      expect(alpha(0, 0), 255);
      expect(
        [
          for (var i = 3; i < data.length; i += 4) data[i],
        ].where((a) => a > 0 && a < 255),
        isNotEmpty,
      );
    },
  );

  testWidgets(
    'real corrected capes exclude the sphere without cropping the canvas',
    (tester) async {
      final g = const FinoraOutfitGeometry(100);
      for (final id in ['new_year', 'star_wanderer', 'neon_noir']) {
        final key = GlobalKey();
        final cape = Wardrobe.item(id)!;
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: g.size.width,
                  height: g.size.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fromRect(
                        rect: g.bodyRect,
                        child: FinoraCapeLayer(item: cape, bodySize: 100),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final image = tester.widget<Image>(find.byType(Image));
        await tester.runAsync(
          () => precacheImage(image.image, tester.element(find.byType(Image))),
        );
        await tester.pumpAndSettle();
        final data = (await capture(tester, key)).buffer.asUint8List();
        final width = (g.size.width * 2).round();
        final center = g.bodyRect.center * 2;
        expect(
          data[((center.dy.round() * width + center.dx.round()) * 4) + 3],
          0,
          reason: id,
        );
        var outsideVisible = 0;
        for (var y = 0; y < (g.size.height * 2).round(); y++) {
          for (var x = 0; x < width; x++) {
            final alpha = data[(y * width + x) * 4 + 3];
            final distance =
                (Offset(x.toDouble(), y.toDouble()) - center).distance;
            if (distance < 98) {
              expect(alpha, 0, reason: '$id leaked into sphere');
            }
            if (distance > 102 && alpha > 50) outsideVisible++;
          }
        }
        expect(outsideVisible, greaterThan(1000), reason: '$id lost its cape');
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'cape mask and the single Finora share animation and breathing phase',
    (tester) async {
      Motion.debugForceAmbient = true;
      addTearDown(() => Motion.debugForceAmbient = false);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: FinoraDressed(
              size: 100,
              rings: false,
              outfit: [Wardrobe.item('new_year')!, Wardrobe.item('moon_cat')!],
            ),
          ),
        ),
      );
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 75));
        final painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((p) => p.painter)
            .whereType<FinoraOrbPainter>()
            .single;
        final cape = tester.widget<FinoraCapeLayer>(
          find.byType(FinoraCapeLayer),
        );
        expect(
          cape.radiusScale,
          closeTo(FinoraOrbPainter.bodyRadiusScale(painter.t), 1e-12),
        );
        final bodyTransforms = tester
            .widgetList<Transform>(
              find.ancestor(
                of: find.byWidgetPredicate(
                  (w) => w is CustomPaint && w.painter is FinoraOrbPainter,
                ),
                matching: find.byType(Transform),
              ),
            )
            .toList();
        final capeTransforms = tester
            .widgetList<Transform>(
              find.ancestor(
                of: find.byType(FinoraCapeLayer),
                matching: find.byType(Transform),
              ),
            )
            .toList();
        expect(bodyTransforms.length, capeTransforms.length);
        for (var i = 0; i < bodyTransforms.length; i++) {
          expect(bodyTransforms[i].transform, capeTransforms[i].transform);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ghost cat and horizontal koi fit narrow phones on light and dark themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final brightness in Brightness.values) {
        for (final pair in [
          ('new_year', 'lilac_ghost'),
          ('frost_queen', 'moon_cat'),
          ('star_wanderer', 'pearl_koi'),
        ]) {
          final (cape, pet) = pair;
          final previewKey = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(brightness, 'coffee'),
              home: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) => RepaintBoundary(
                      key: previewKey,
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: FinoraDressed(
                            size: 120,
                            rings: false,
                            outfit: [Wardrobe.item(cape)!, Wardrobe.item(pet)!],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          for (final image
              in tester.widgetList<Image>(find.byType(Image)).toList()) {
            await tester.runAsync(
              () => precacheImage(
                image.image,
                tester.element(find.byType(FinoraDressed)),
              ),
            );
          }
          await tester.pumpAndSettle();
          final size = tester.getSize(find.byType(FinoraDressed));
          expect(size.width, lessThanOrEqualTo(280));
          expect(find.byType(FinoraCharacter), findsOneWidget);
          expect(find.byType(WardrobePiece), findsOneWidget);
          expect(find.byType(FinoraCapeLayer), findsOneWidget);
          for (final image in tester.widgetList<RawImage>(
            find.byType(RawImage),
          )) {
            expect(image.image, isNotNull, reason: pet);
          }
          expect(tester.takeException(), isNull, reason: '$brightness/$pet');
          final previewDirectory = Platform.environment['WARDROBE_PREVIEW_DIR'];
          if (previewDirectory != null) {
            await tester.runAsync(
              () => Directory(previewDirectory).create(recursive: true),
            );
            final boundary =
                previewKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final frame = (await tester.runAsync(
              () => boundary.toImage(pixelRatio: 2),
            ))!;
            final png = (await tester.runAsync(
              () => frame.toByteData(format: ui.ImageByteFormat.png),
            ))!;
            await tester.runAsync(
              () => File(
                '$previewDirectory/${brightness.name}-$cape-$pet.png',
              ).writeAsBytes(png.buffer.asUint8List()),
            );
            frame.dispose();
          }
        }
      }
    },
  );
}
