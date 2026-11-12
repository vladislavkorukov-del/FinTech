import 'dart:io';
import 'dart:ui' as ui;

import 'package:finora/domain/flow/flow.dart';
import 'package:finora/presentation/screens/world/flow_art.dart';
import 'package:finora/presentation/screens/world/flow_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/screenshot_fonts.dart';

void main() {
  testWidgets(
    'original square pieces and obstacle states remain separate layers at64px',
    (tester) async {
      final level = FlowLevels.decode(
        File('assets/flow/levels.json').readAsStringSync(),
      ).first;
      final base = FlowEngine.newGame(level);
      final board = [...base.board];
      for (var i = 0; i < FlowTile.values.length; i++) {
        board[i] = FlowCell(tile: FlowTile.values[i]);
      }
      board[8] = const FlowCell(tile: FlowTile.coin, ice: 2);
      board[9] = const FlowCell(tile: FlowTile.wallet, ice: 1);
      board[10] = const FlowCell(tile: FlowTile.shield, chain: 2);
      board[11] = const FlowCell(tile: FlowTile.goal, chain: 1);
      board[12] = const FlowCell(crate: 2);
      board[13] = const FlowCell(crate: 1);
      board[16] = const FlowCell(
        tile: FlowTile.coin,
        booster: FlowBooster.rocketRow,
      );
      board[17] = const FlowCell(
        tile: FlowTile.wallet,
        booster: FlowBooster.rocketColumn,
      );
      board[18] = const FlowCell(
        tile: FlowTile.goal,
        booster: FlowBooster.bomb,
      );
      board[19] = const FlowCell(booster: FlowBooster.core);
      board[20] = const FlowCell(
        tile: FlowTile.chart,
        booster: FlowBooster.drone,
      );
      board[24] = const FlowCell(stack: 3);
      final session = FlowSession(
        levelId: 1,
        board: board,
        remainingMoves: 10,
        score: 0,
        progress: const {},
        rngState: base.rngState,
      );
      final output = Platform.environment['FINORA_FLOW_CAPTURE_DIR'];
      if (output != null) await tester.runAsync(loadScreenshotFonts);
      tester.view.physicalSize = const Size(560, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(560, 600),
              devicePixelRatio: 2,
            ),
            child: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: const ValueKey('pieces-capture'),
                  child: SizedBox.square(
                    dimension: 533,
                    child: FlowBoard(
                      session: session,
                      onSelect: (_) {},
                      onExchange: (_, _) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(FlowBoard));
      await tester.runAsync(() => FlowArt.precacheVisible(context));
      await tester.pumpAndSettle();
      for (final (index, asset) in [
        (8, 'obstacle_ice_intact'),
        (9, 'obstacle_ice_cracked'),
        (10, 'obstacle_chain_intact'),
        (11, 'obstacle_chain_damaged'),
        (12, 'obstacle_crate_intact'),
        (13, 'obstacle_crate_damaged'),
        (16, 'match3_rocket_horizontal'),
        (17, 'match3_rocket_vertical'),
        (18, 'booster_bomb'),
        (19, 'match3_rainbow_sphere'),
      ]) {
        final cell = find.byKey(ValueKey('flow-cell-$index'));
        final art = find.descendant(
          of: cell,
          matching: find.byWidgetPredicate(
            (w) => w is FlowSprite && w.id == asset,
          ),
        );
        expect(art, findsOneWidget);
        expect(tester.widget<FlowSprite>(art).trim, isFalse);
        expect(tester.getSize(art), tester.getSize(cell));
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('flow-cell-8')),
          matching: find.byWidgetPredicate(
            (w) => w is FlowSprite && w.id == 'match3_coin',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('flow-cell-12')),
          matching: find.byWidgetPredicate(
            (w) => w is FlowSprite && w.id.startsWith('match3_'),
          ),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      if (output != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('pieces-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/pieces-and-obstacles.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
