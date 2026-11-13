import 'dart:io';

import 'package:finora/domain/flow/flow.dart';
import 'package:finora/presentation/screens/world/flow_board.dart';
import 'package:finora/presentation/screens/world/flow_chapters.dart';
import 'package:finora/presentation/screens/world/flow_map_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1.64: painted chapters — a backdrop per chapter of 50 levels and the
/// chapter's part on the level map, joined in pack order.
void main() {
  test('chapter 1 keeps the sky; chapters 2–10 take the nine themes', () {
    expect(FlowPlayfield.backgroundFor(1), FlowPlayfield.background);
    expect(FlowChapters.of(1), isNull);
    final keys = [for (var c = 2; c <= 10; c++) FlowChapters.of(c)!.key];
    expect(keys, [
      'sakura',
      'jade',
      'lagoon',
      'dunes',
      'autumn',
      'amethyst',
      'ice',
      'storm',
      'moon',
    ]);
    expect(FlowChapters.forLevel(50), isNull);
    expect(FlowChapters.forLevel(51)!.key, 'sakura');
    expect(FlowChapters.forLevel(500)!.key, 'moon');
    expect(FlowPlayfield.backgroundFor(10), FlowChapters.of(10)!.background);
  });

  test('every theme ships both files at the size the pack states', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final pack = File('docs/match3_pack/chapters.json').readAsStringSync();
    for (final t in FlowChapters.themes) {
      for (final asset in [t.background, t.map]) {
        expect(pack, contains(asset));
        final data = await rootBundle.load(asset);
        expect(data.lengthInBytes, greaterThan(10000), reason: asset);
      }
    }
  });

  test('map periods follow the chapters, top to bottom', () {
    const top = flowLevelCount;
    // Period 0 holds levels 488–500 (moon), the last periods are terraces.
    expect(FlowMapGeometry.themeOf(0, top)!.key, 'moon');
    final last = (top - 1) ~/ 13;
    expect(FlowMapGeometry.themeOf(last, top), isNull);
    // Going down the map the themes come in reverse pack order, never
    // skipping one, and the lowest theme (sakura) sits on the terraces.
    final order = <String>[];
    for (var q = 0; q <= last; q++) {
      final t = FlowMapGeometry.themeOf(q, top)?.key ?? 'terraces';
      if (order.isEmpty || order.last != t) order.add(t);
    }
    expect(order, [
      'moon',
      'storm',
      'ice',
      'amethyst',
      'autumn',
      'dunes',
      'lagoon',
      'jade',
      'sakura',
      'terraces',
    ]);
  });

  testWidgets('the map draws a chapter part where its levels are', (
    tester,
  ) async {
    final made = FlowLevels.decode(
      File('assets/flow/levels.json').readAsStringSync(),
    );
    final levels = [...made, ...FlowLevelGenerator.all()];
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: FlowTerraceMap(
          levels: levels,
          progress: FlowProgress(
            results: {
              for (var i = 1; i < 101; i++)
                i: const FlowResult(stars: 1, bestScore: 1),
            },
          ),
          onOpen: (_) {},
          onBack: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('flow-level-101')), findsOneWidget);
    final parts = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('flow-map-part-'),
    );
    expect(parts, findsWidgets);
    final names = tester
        .widgetList(parts)
        .map((w) => (w.key! as ValueKey<String>).value)
        .join(' ');
    expect(names, anyOf(contains('jade'), contains('sakura')));
    expect(tester.takeException(), isNull);
  });
}
