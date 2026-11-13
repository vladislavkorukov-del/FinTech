import 'dart:io';

import 'package:finora/domain/flow/flow.dart';
import 'package:finora/presentation/screens/world/flow_art.dart';
import 'package:finora/presentation/screens/world/flow_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1.62: the paper-plane drone — its own art on the board, a hover while it
/// waits, and a flight to the one cell it strikes before the board refills.
void main() {
  final level = FlowLevels.decode(
    File('assets/flow/levels.json').readAsStringSync(),
  ).first;

  FlowSession withDrone() {
    final base = FlowEngine.newGame(level);
    final board = [...base.board];
    board[27] = const FlowCell(
      tile: FlowTile.wallet,
      booster: FlowBooster.drone,
    );
    board[28] = const FlowCell(tile: FlowTile.shield);
    return FlowSession(
      levelId: level.id,
      board: board,
      remainingMoves: 9,
      score: 0,
      progress: const {},
      rngState: base.rngState,
    );
  }

  Finder sprite(String id) =>
      find.byWidgetPredicate((w) => w is FlowSprite && w.id == id);

  double opacityOf(WidgetTester tester, int cell) => tester
      .widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(ValueKey('flow-cell-$cell')),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;

  Widget host(
    FlowSession session, {
    FlowBoardMotion? motion,
    bool animate = true,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox.square(
          dimension: 380,
          child: FlowBoard(
            session: session,
            motion: motion,
            animate: animate,
            onSelect: (_) {},
            onExchange: (_, _) {},
          ),
        ),
      ),
    ),
  );

  testWidgets('the drone is the pack\'s paper plane, still without motion', (
    tester,
  ) async {
    await tester.pumpWidget(host(withDrone(), animate: false));
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('flow-cell-27'));
    final plane = find.descendant(of: cell, matching: sprite('match3_drone'));
    expect(plane, findsOneWidget);
    expect(tester.widget<FlowSprite>(plane).trim, isFalse);
    expect(tester.getSize(plane), tester.getSize(cell));
    expect(find.byIcon(Icons.flight_outlined), findsNothing);
    expect(
      FlowArt.path('match3_drone'),
      'assets/finora/match3/special/match3_drone.png',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('swapped with a shield, the drone flies to its target first', (
    tester,
  ) async {
    final before = withDrone();
    await tester.pumpWidget(host(before));
    await tester.pump(const Duration(seconds: 1)); // the board fills
    // Waiting on the board, the plane hovers.
    expect(tester.hasRunningAnimations, isTrue);

    final turn = FlowEngine.swap(level, before, 27, 28);
    expect(turn.accepted, isTrue);
    expect(turn.session.remainingMoves, 8); // the move is spent
    final motion = FlowBoardMotion(
      id: 1,
      before: before.board,
      accepted: true,
      from: 27,
      to: 28,
      events: turn.events,
    );
    // The shield takes the drone's place; the drone strikes the first coin.
    final flight = motion.flights.single;
    expect(flight.from, 28);
    final coins = [
      for (var i = 0; i < 64; i++)
        if (before.board[i].tile == FlowTile.coin &&
            before.board[i].booster == FlowBooster.none)
          i,
    ];
    expect(flight.to, coins.first);
    expect(turn.session.progress['collect:coin'], greaterThanOrEqualTo(1));

    await tester.pumpWidget(host(turn.session, motion: motion));
    // Swap (170 ms), then mid-flight.
    await tester.pump(const Duration(milliseconds: 170 + 230));
    final plane = find.byKey(const ValueKey('flow-drone-flight-28'));
    expect(plane, findsOneWidget);
    expect(
      find.descendant(of: plane, matching: sprite('match3_drone')),
      findsOneWidget,
    );
    // It is in the air, on an arc above the straight path, turned along it.
    final from = tester.getCenter(find.byKey(const ValueKey('flow-cell-28')));
    final to = tester.getCenter(find.byKey(ValueKey('flow-cell-${flight.to}')));
    expect(tester.getCenter(plane).dy, lessThan((from.dy + to.dy) / 2));
    final turned = tester.widget<Transform>(
      find.descendant(of: plane, matching: find.byType(Transform)).first,
    );
    expect(turned.transform.isIdentity(), isFalse);
    // The drone's cell is empty in the air; the target waits for it.
    expect(opacityOf(tester, 28), 0);
    expect(opacityOf(tester, flight.to), 1);

    // On arrival the plane is gone and the target pops.
    await tester.pump(const Duration(milliseconds: 230 + 90));
    expect(plane, findsNothing);
    expect(opacityOf(tester, flight.to), lessThan(1));

    // The board refills and settles; nothing is left over.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 7));
    expect(tester.takeException(), isNull);
  });
}
