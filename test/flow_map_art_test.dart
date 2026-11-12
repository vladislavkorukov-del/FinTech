import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:finora/domain/flow/flow.dart';
import 'package:finora/presentation/screens/world/flow_map_scene.dart';
import 'package:finora/presentation/screens/world/flow_art.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/screenshot_fonts.dart';

void main() {
  final levels = FlowLevels.decode(
    File('assets/flow/levels.json').readAsStringSync(),
  );
  final original = levels.where((l) => l.id <= 20).toList();

  test(
    'terrace geometry repeats ABC and13 anchors without renumbering levels',
    () {
      expect(FlowMapGeometry.backgroundIndex(-4), 2);
      expect(FlowMapGeometry.backgroundIndex(-3), 0);
      expect(FlowMapGeometry.backgroundIndex(-2), 1);
      expect(FlowMapGeometry.backgroundIndex(-1), 2);
      expect(FlowMapGeometry.backgroundIndex(0), 0);
      expect(FlowMapGeometry.backgroundIndex(1), 1);
      expect(FlowMapGeometry.backgroundIndex(2), 2);
      expect(FlowMapGeometry.backgroundIndex(3), 0);
      expect(FlowMapGeometry.anchors.length, 13);
      expect(FlowMapGeometry.anchor(21, 21).x, 240);
      expect(FlowMapGeometry.worldY(21, 21), 145);
      expect(FlowMapGeometry.worldY(20, 21), 308);
      expect(FlowMapGeometry.anchor(16, 21).width, 130);
      expect(FlowMapGeometry.anchor(8, 21).x, 240);
      expect(FlowMapGeometry.worldY(8, 21), 2172 + 145);
      for (var id = 1; id < 500; id++) {
        expect(
          FlowMapGeometry.worldY(id + 1, 500),
          lessThan(FlowMapGeometry.worldY(id, 500)),
        );
      }
    },
  );

  test('compiled geometry agrees with the supplied artist layout', () {
    final source =
        jsonDecode(
              File(
                'assets/finora/match3/map/map_layout.json',
              ).readAsStringSync(),
            )
            as Map;
    expect(FlowMapGeometry.referenceWidth, source['reference_width']);
    expect(FlowMapGeometry.sectionHeight, source['section_height']);
    expect(FlowMapGeometry.periodHeight, source['period_height']);
    final anchors = source['platform_anchors'] as List;
    expect(FlowMapGeometry.anchors.length, anchors.length);
    for (var i = 0; i < anchors.length; i++) {
      final raw = anchors[i] as Map;
      final actual = FlowMapGeometry.anchors[i];
      expect(actual.x, raw['x']);
      expect(actual.y, raw['y']);
      expect(actual.width, raw['visible_node_width']);
      expect(FlowMapGeometry.baseYOffset, raw['base_y_offset']);
    }
  });

  test('shared physical section edges do not accumulate rounding drift', () {
    for (final width in [320.0, 390.0, 412.0, 740.0]) {
      for (final dpr in [1.0, 1.5, 2.625, 3.0]) {
        for (var section = -6; section <= 500; section++) {
          final edge = FlowMapGeometry.boundary(section, width, dpr);
          final physical = edge * dpr;
          expect(physical, closeTo(physical.roundToDouble(), 1e-7));
          expect(
            edge,
            closeTo(
              ((724 + section * 724) * width / 724 * dpr).round() / dpr,
              1e-7,
            ),
          );
          final next = FlowMapGeometry.boundary(section + 1, width, dpr);
          expect((next - edge) * dpr, closeTo(width * dpr, 1.000001));
        }
      }
    }
  });

  Future<void> mount(
    WidgetTester tester, {
    required FlowProgress progress,
    required List<int> opened,
    List<FlowLevel>? catalog,
    Size size = const Size(390, 844),
    double dpr = 1,
    double scale = 1,
    VoidCallback? onBack,
  }) async {
    tester.view.physicalSize = size * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark, 'coffee'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
            viewPadding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('map-capture'),
          child: FlowTerraceMap(
            levels: catalog ?? original,
            progress: progress,
            onOpen: (level) => opened.add(level.id),
            onBack: onBack ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'current node opens; locked node cannot start; pinned back works',
    (tester) async {
      final opened = <int>[];
      var back = false;
      await mount(
        tester,
        progress: const FlowProgress(),
        opened: opened,
        dpr: 2.625,
        onBack: () => back = true,
      );
      final current = find.byKey(const ValueKey('flow-level-1'));
      final locked = find.byKey(const ValueKey('flow-level-2'));
      expect(current.hitTestable(), findsOneWidget);
      await tester.tap(current);
      expect(opened, [1]);
      final blocked = tester.widget<InkWell>(locked);
      expect(blocked.onTap, isNull);
      await tester.ensureVisible(locked);
      await tester.tap(locked);
      expect(opened, [1]);
      final header = find.byKey(const ValueKey('flow-map-header'));
      final before = tester.getRect(header);
      await tester.drag(
        find.byKey(const ValueKey('flow-map-scroll')),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(header), before);
      final backButton = find.byKey(const ValueKey('flow-map-back'));
      expect(tester.getSize(backButton).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(backButton).height, greaterThanOrEqualTo(48));
      await tester.tap(backButton);
      expect(back, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completed nodes retain stars and open while numbering rises up',
    (tester) async {
      final opened = <int>[];
      const progress = FlowProgress(
        results: {
          1: FlowResult(stars: 2, bestScore: 1000),
          2: FlowResult(stars: 3, bestScore: 2000),
        },
      );
      await mount(tester, progress: progress, opened: opened);
      final current = find.byKey(const ValueKey('flow-level-3'));
      expect(current.hitTestable(), findsOneWidget);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      position.jumpTo(0);
      await tester.pumpAndSettle();
      final completed = find.byKey(const ValueKey('flow-level-1'));
      await tester.scrollUntilVisible(completed, 180, maxScrolls: 40);
      await tester.pumpAndSettle();
      await tester.tap(completed);
      expect(opened, [1]);
      expect(
        find.bySemanticsLabel(RegExp('Уровень 1.*2 из 3 звёзд')),
        findsOneWidget,
      );
      final first = tester.getRect(completed);
      final second = tester.getRect(find.byKey(const ValueKey('flow-level-2')));
      expect(second.center.dy, lessThan(first.center.dy));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('map uses bounded textures and nodes even for a long catalog', (
    tester,
  ) async {
    final catalog = List.generate(
      500,
      (i) => FlowLevel(
        id: i + 1,
        name: 'Уровень ${i + 1}',
        seed: i + 1,
        moves: 20,
        goals: const [FlowGoal('collect:coin', 10)],
        scoreThresholds: const [100, 200, 300],
      ),
    );
    await mount(
      tester,
      progress: const FlowProgress(),
      opened: [],
      catalog: catalog,
    );
    expect(find.byKey(const ValueKey('flow-level-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-level-500')), findsNothing);
    expect(
      find
          .byWidgetPredicate(
            (w) => w.key.toString().contains('flow-map-section-'),
          )
          .evaluate()
          .length,
      lessThan(9),
    );
    expect(
      find
          .byWidgetPredicate((w) => w.key.toString().contains('flow-level-'))
          .evaluate()
          .length,
      lessThan(30),
    );
    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flow-level-500')), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-level-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'map remains accessible at small widths, landscape and text200%',
    (tester) async {
      for (final size in [const Size(320, 640), const Size(740, 360)]) {
        await mount(
          tester,
          progress: const FlowProgress(),
          opened: [],
          size: size,
          dpr: 1.5,
          scale: 2,
        );
        final current = find.byKey(const ValueKey('flow-level-1'));
        expect(current.hitTestable(), findsOneWidget);
        final currentRect = tester.getRect(current);
        final header = tester.getRect(
          find.byKey(const ValueKey('flow-map-header')),
        );
        expect(currentRect.top, greaterThanOrEqualTo(header.bottom));
        expect(currentRect.bottom, lessThanOrEqualTo(size.height - 24));
        expect(currentRect.width, greaterThanOrEqualTo(48));
        expect(currentRect.height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('actual terrace map sprites decode for the visual check', (
    tester,
  ) async {
    final output = Platform.environment['FINORA_MAP_CAPTURE_DIR'];
    if (output != null) await tester.runAsync(loadScreenshotFonts);
    final progress = FlowProgress(
      results: {
        for (var id = 1; id <= 11; id++)
          id: const FlowResult(stars: 3, bestScore: 2200),
      },
    );
    await mount(
      tester,
      progress: progress,
      opened: [],
      dpr: output == null ? 1 : 2,
    );
    final context = tester.element(find.byType(FlowTerraceMap));
    final images = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .toSet();
    await tester.runAsync(() async {
      await Future.wait(images.map((image) => precacheImage(image, context)));
      await FlowArt.precacheVisible(context);
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (output != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('map-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/map.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
