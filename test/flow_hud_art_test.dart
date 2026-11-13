import 'dart:io';

import 'package:finora/domain/flow/flow.dart';
import 'package:finora/presentation/screens/world/flow_dialogs.dart';
import 'package:finora/presentation/screens/world/flow_hud.dart';
import 'package:finora/presentation/screens/world/flow_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Art with words baked in; 1.63 draws all words as live Finora Potok.
const _baked = [
  'hud_moves_card',
  'hud_goals_card',
  'hud_level_label',
  'pause_title',
  'pause_button_continue',
  'pause_button_restart',
  'pause_button_exit',
  'victory_title',
  'victory_label_score',
  'victory_label_reward',
  'victory_label_next',
  'victory_label_levels',
  'out_of_moves_title',
  'out_of_moves_label_remaining',
  'out_of_moves_label_extra_moves',
  'out_of_moves_label_restart',
  'out_of_moves_label_levels',
  'prelevel_label_moves',
  'prelevel_label_goals',
  'prelevel_label_boosters',
  'prelevel_label_play',
  'map_label_levels',
];

Finder _sprite(String id) =>
    find.byWidgetPredicate((w) => w is FlowSprite && w.id == id);

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  required Size size,
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

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

  final level = FlowLevels.decode(
    File('assets/flow/levels.json').readAsStringSync(),
  ).first;
  FlowSession session({int moves = 9, int score = 0}) {
    final base = FlowEngine.newGame(level);
    return FlowSession(
      levelId: level.id,
      board: base.board,
      remainingMoves: moves,
      score: score,
      progress: const {},
      rngState: base.rngState,
    );
  }

  testWidgets(
    '1.63: compact HUD on empty library plates with live, unified text',
    (tester) async {
      for (final (width, scale) in [(320.0, 2.0), (430.0, 1.0)]) {
        await _mount(
          tester,
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width - 16,
              child: FlowTopHud(
                level: level,
                session: session(moves: 123, score: 98765),
                onPause: () {},
              ),
            ),
          ),
          size: Size(width, 700),
          scale: scale,
        );
        expect(
          tester.getSize(find.byType(FlowTopHud)).height,
          closeTo(FlowTopHud.heightFor(width - 16), .5),
        );
        expect(FlowTopHud.heightFor(width), lessThanOrEqualTo(150));
        expect(find.text('Уровень ${level.id}'), findsOneWidget);
        expect(find.text('ХОДЫ'), findsOneWidget);
        expect(find.text('ЦЕЛИ'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('flow-hud-moves')),
            matching: find.text('123'),
          ),
          findsOneWidget,
        );
        for (final id in _baked) {
          expect(_sprite(id), findsNothing, reason: id);
        }
        expect(
          tester.getSize(find.byKey(const ValueKey('flow-pause'))),
          const Size(48, 48),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    '1.62: booster slots hold badge bottom-left and «+» bottom-right with apart targets',
    (tester) async {
      for (final width in [320.0, 390.0, 430.0]) {
        final used = <FlowTool>[], more = <FlowTool>[];
        await _mount(
          tester,
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: width - 16,
              child: FlowBottomTools(
                flow: const FlowProgress(),
                onUse: used.add,
                onMore: more.add,
              ),
            ),
          ),
          size: Size(width, 400),
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('flow-bottom-panel')))
              .height,
          closeTo(FlowBottomTools.heightFor(width - 16), .5),
        );
        expect(_sprite('booster_slot'), findsNWidgets(4));
        expect(_sprite('booster_counter_badge'), findsNWidgets(4));
        expect(_sprite('booster_plus_button'), findsNWidgets(4));
        for (final tool in FlowTool.values) {
          final button = find.byKey(ValueKey('flow-tool-${tool.name}'));
          final plus = find.byKey(ValueKey('flow-tool-more-${tool.name}'));
          final slot = tester.getRect(button);
          expect(tester.getSize(plus), const Size(48, 48));
          // The slot's centre belongs to the booster, not to its «+».
          expect(tester.getRect(plus).contains(slot.center), isFalse);
          final badge = tester.getRect(
            find
                .descendant(
                  of: find.ancestor(of: button, matching: find.byType(Stack)),
                  matching: _sprite('booster_counter_badge'),
                )
                .first,
          );
          final plusArt = tester.getRect(
            find.descendant(of: plus, matching: _sprite('booster_plus_button')),
          );
          expect(badge.center.dx, lessThan(slot.center.dx));
          expect(badge.center.dy, greaterThan(slot.center.dy));
          expect(plusArt.center.dx, greaterThan(slot.center.dx));
          expect(plusArt.center.dy, greaterThan(slot.center.dy));
          expect(slot.inflate(1).contains(plusArt.center), isTrue);
          await tester.tapAt(slot.center);
          await tester.tapAt(tester.getRect(plus).center);
          await tester.pump();
        }
        expect(used, FlowTool.values);
        expect(more, FlowTool.values);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    '1.63: victory has live text on empty bases and keeps four actions on a small phone',
    (tester) async {
      final taps = <String>[];
      final won = session(moves: 3, score: 1234567);
      await _mount(
        tester,
        FlowOverlay(
          art: 'victory_panel_base',
          child: FlowVictoryContent(
            level: level,
            session: won,
            reward: 100000,
            onNext: () => taps.add('next'),
            onLevels: () => taps.add('levels'),
            onReplay: () => taps.add('replay'),
            onExitWorld: () => taps.add('world'),
          ),
        ),
        size: const Size(320, 568),
        scale: 1.3,
      );
      for (final id in _baked) {
        expect(_sprite(id), findsNothing, reason: id);
      }
      for (final text in [
        'Уровень пройден!',
        'Очки',
        'Награда',
        'Дальше',
        'К уровням',
        'Повторить уровень',
        'В Мир Финоры',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text(flowNumber(1234567)), findsOneWidget);
      expect(find.text(flowNumber(100000)), findsOneWidget);
      for (final (key, name) in [
        ('flow-next', 'next'),
        ('flow-map', 'levels'),
        ('flow-replay', 'replay'),
        ('flow-exit-world', 'world'),
      ]) {
        final target = find.byKey(ValueKey(key));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
        await tester.tap(target);
        await tester.pump();
        expect(taps.last, name);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
