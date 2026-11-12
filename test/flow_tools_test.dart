import 'dart:convert';
import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/flow/flow.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

FlowLevel obstacles() => const FlowLevel(
  id: 1,
  name: 'Overlay compatibility',
  seed: 123,
  moves: 20,
  goals: [FlowGoal('chain', 1), FlowGoal('crate', 1)],
  obstacles: [FlowObstacle(20, 'chain', 2), FlowObstacle(21, 'crate', 2)],
  scoreThresholds: [0, 200, 600],
);

void main() {
  sqfliteFfiInit();

  test('legacy schema keeps exactly the same cell and session JSON', () {
    final legacy = {'tile': 'coin', 'booster': 'none', 'ice': 0, 'stack': 0};
    final cell = FlowCell.fromJson(legacy);
    expect(cell.chain, 0);
    expect(cell.crate, 0);
    expect(cell.toJson(), legacy);
    final level = FlowLevels.decode(
      File('assets/flow/levels.json').readAsStringSync(),
    ).first;
    final original = FlowEngine.newGame(level).toJson();
    final restored = FlowSession.fromJson(Map<String, dynamic>.from(original));
    expect(restored.toJson(), original);
    expect(restored.bonusMoves, 0);
    expect(restored.usedTools, isEmpty);
    final progress = FlowProgress.fromJson({'version': 1, 'results': {}});
    for (final tool in FlowTool.values) {
      expect(progress.available(tool), FlowToolRules.initialStock[tool]);
    }
    expect(progress.music, isFalse);
    expect(progress.sound, isTrue);
    expect(progress.haptics, isTrue);
  });

  test('chains retain the underlying tile through both damage stages', () {
    final level = obstacles();
    FlowLevels.validate(level);
    var state = FlowEngine.newGame(level);
    final tile = state.board[20].tile;
    expect(state.board[20].movable, isFalse);
    final first = FlowEngine.useTool(level, state, FlowTool.hammer, cell: 20);
    expect(first.accepted, isTrue);
    expect(first.session.board[20].chain, 1);
    expect(first.session.board[20].tile, tile);
    expect(first.session.progress['chain'] ?? 0, 0);
    expect(first.session.remainingMoves, state.remainingMoves);
    FlowEngine.validateSession(level, first.session);
    state = FlowEngine.useTool(
      level,
      first.session,
      FlowTool.hammer,
      cell: 20,
    ).session;
    expect(state.board[20].chain, 0);
    expect(state.board[20].tile, tile);
    expect(state.board[20].movable, isTrue);
    expect(state.progress['chain'], 1);
    FlowEngine.validateSession(level, state);
    expect(
      FlowSession.fromJson(Map<String, dynamic>.from(state.toJson())).toJson(),
      state.toJson(),
    );
  });

  test(
    'crates stay separate from receipt stacks and damage once per hit event',
    () {
      final level = obstacles();
      final state = FlowEngine.newGame(level);
      expect(state.board[21].tile, isNull);
      expect(state.board[21].stack, 0);
      final first = FlowEngine.useTool(level, state, FlowTool.hammer, cell: 21);
      expect(first.session.board[21].crate, 1);
      expect(first.session.progress['crate'] ?? 0, 0);
      final second = FlowEngine.useTool(
        level,
        first.session,
        FlowTool.hammer,
        cell: 21,
      );
      expect(second.session.board[21].crate, 0);
      expect(second.session.board[21].tile, isNotNull);
      expect(second.session.progress['crate'], 1);
      FlowEngine.validateSession(level, second.session);
      final blast = FlowEngine.useTool(level, state, FlowTool.bomb, cell: 20);
      expect(
        blast.events
            .where(
              (e) => e.chain == 0 && e.kind == 'crateDamage' && e.index == 21,
            )
            .length,
        1,
      );
    },
  );

  test(
    'invalid overlays, inflated strength and mixed blockers are rejected',
    () {
      for (final cell in [
        const FlowCell(tile: FlowTile.coin, chain: 3),
        const FlowCell(tile: FlowTile.coin, chain: 1, ice: 1),
        const FlowCell(crate: 1, stack: 1),
        const FlowCell(tile: FlowTile.coin, crate: 1),
        const FlowCell(chain: 1),
      ]) {
        expect(
          () => FlowCell.fromJson(Map<String, dynamic>.from(cell.toJson())),
          throwsFormatException,
        );
      }
    },
  );

  test('ledger merges only forwards and malformed stock fails closed', () {
    final spent = const FlowProgress()
        .consume(FlowTool.hammer)
        .consume(FlowTool.extraMoves);
    final old = FlowProgress.fromJson({'version': 1, 'results': {}});
    expect(FlowProgress.merge(spent, old).available(FlowTool.hammer), 1);
    expect(FlowProgress.merge(old, spent).available(FlowTool.extraMoves), 0);
    final restored = FlowProgress.fromJson(
      Map<String, dynamic>.from(spent.toJson()),
    );
    expect(restored.spent, spent.spent);
    final malformed = FlowProgress.fromJson({
      'version': 1,
      'spent': {'hammer': -1},
    });
    expect(
      FlowTool.values.every((tool) => malformed.available(tool) == 0),
      isTrue,
    );
  });

  group('atomic inventory and preferences in the existing repository', () {
    late Directory dir;
    late FinanceRepository repo;
    late FinanceController c;
    late FlowLevel level;
    String dbPath() => '${dir.path}/ledger';
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('flow-tools-');
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: dbPath(),
      );
      await repo.save(
        const FinanceData(
          accounts: [Account(id: 'a', name: 'Карта', openingMinor: 123456)],
          members: [Member(id: 'me', name: 'Я')],
        ),
      );
      c = FinanceController(repo, _Quiet(), await repo.load());
      await c.syncWorld();
      level = FlowLevels.decode(
        File('assets/flow/levels.json').readAsStringSync(),
      ).first;
    });
    tearDown(() async {
      c.dispose();
      await repo.close();
      await dir.delete(recursive: true);
    });
    Future<void> restart() async {
      c.dispose();
      await repo.close();
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: dbPath(),
      );
      c = FinanceController(repo, _Quiet(), await repo.load());
    }

    test(
      'preferences are independent, survive restart and never affect money',
      () async {
        await c.setFlowPreferences(music: true);
        await c.setFlowPreferences(haptics: false);
        await restart();
        expect(c.data.world.flow.music, isTrue);
        expect(c.data.world.flow.sound, isTrue);
        expect(c.data.world.flow.haptics, isFalse);
        await c.setFlowPreferences(sound: false);
        expect(c.data.world.flow.music, isTrue);
        expect(c.data.world.flow.haptics, isFalse);
        expect(c.data.world.flow.sound, isFalse);
        expect(c.balance, 123456);
        expect(c.data.entries, isEmpty);
      },
    );

    test(
      'prelevel tools spend on successful launch only and queued duplicate is rejected',
      () async {
        final initial = c.data.world.flow.toJson();
        await expectLater(
          c.startFlow(level, restart: true, tools: {FlowTool.hammer}),
          throwsFormatException,
        );
        expect(c.data.world.flow.toJson(), initial);
        final first = c.startFlow(
          level,
          restart: true,
          tools: {FlowTool.extraMoves},
        );
        final duplicate = c.startFlow(
          level,
          restart: true,
          tools: {FlowTool.extraMoves},
        );
        await expectLater(duplicate, throwsFormatException);
        await first;
        final state = c.data.world.flow.session!;
        expect(state.remainingMoves, level.moves + 5);
        expect(state.usedTools[FlowTool.extraMoves], 1);
        expect(c.data.world.flow.available(FlowTool.extraMoves), 0);
        await restart();
        expect(c.data.world.flow.session!.toJson(), state.toJson());
        await c.startFlow(level, restart: true);
        expect(c.data.world.flow.available(FlowTool.extraMoves), 0);
        expect(c.data.world.flow.session!.remainingMoves, level.moves);
        expect(c.balance, 123456);
      },
    );

    test(
      'all permitted prelevel tools apply once and bonus survives ordinary moves',
      () async {
        const practice = FlowLevel(
          id: 1,
          name: 'Tools',
          seed: 123,
          moves: 20,
          goals: [FlowGoal('collect:coin', 9999)],
          scoreThresholds: [0, 200, 600],
        );
        await c.startFlow(
          practice,
          restart: true,
          tools: FlowToolRules.prelevel,
        );
        var state = c.data.world.flow.session!;
        expect(state.remainingMoves, 25);
        expect(state.bonusMoves, 5);
        for (final tool in FlowToolRules.prelevel) {
          expect(c.data.world.flow.available(tool), 0);
          expect(state.usedTools[tool], 1);
        }
        FlowEngine.validateSession(practice, state);
        final move = FlowEngine.legalMoves(state).first;
        await c.swapFlow(practice, state, move.$1, move.$2);
        state = c.data.world.flow.session!;
        expect(state.remainingMoves, 24);
        expect(state.bonusMoves, 5);
        expect(state.usedTools[FlowTool.extraMoves], 1);
        await restart();
        expect(c.data.world.flow.session!.toJson(), state.toJson());
      },
    );

    test(
      'tool victory finalizes stars and rewards once without renewing stock',
      () async {
        const base = FlowLevel(
          id: 1,
          name: 'One tile',
          seed: 123,
          moves: 20,
          goals: [FlowGoal('collect:coin', 9999)],
          scoreThresholds: [0, 200, 600],
        );
        final tile = FlowEngine.newGame(base).board[0].tile!;
        final winning = FlowLevel(
          id: 1,
          name: 'One tile',
          seed: 123,
          moves: 20,
          goals: [FlowGoal('collect:${tile.name}', 1)],
          scoreThresholds: const [0, 200, 600],
        );
        await c.startFlow(winning);
        await c.useFlowTool(
          winning,
          c.data.world.flow.session!,
          FlowTool.hammer,
          cell: 0,
        );
        expect(c.data.world.flow.session!.status, FlowStatus.won);
        expect(c.data.world.flow.results[1], isNotNull);
        expect(c.data.world.rewards.containsKey('flow:level:1:v1'), isTrue);
        final rewards = Map.of(c.data.world.rewards);
        final sparks = c.data.world.sparks;
        await c.startFlow(winning, restart: true);
        await c.useFlowTool(
          winning,
          c.data.world.flow.session!,
          FlowTool.hammer,
          cell: 0,
        );
        expect(c.data.world.flow.session!.status, FlowStatus.won);
        expect(c.data.world.flow.available(FlowTool.hammer), 0);
        expect(c.data.world.rewards, rewards);
        expect(c.data.world.sparks, sparks);
        await expectLater(
          c.useFlowTool(
            winning,
            c.data.world.flow.session!,
            FlowTool.extraMoves,
          ),
          completes,
        );
        expect(c.data.world.flow.available(FlowTool.extraMoves), 1);
      },
    );

    test('failed SQL commit rolls back launch or tool with its stock', () async {
      final db = await databaseFactoryFfi.openDatabase(dbPath());
      await db.execute(
        "CREATE TRIGGER reject_flow_tool BEFORE INSERT ON settings WHEN NEW.key='finora_world' BEGIN SELECT RAISE(ABORT,'tool write failure'); END",
      );
      var before = c.data.toJson();
      await expectLater(
        c.startFlow(level, restart: true, tools: {FlowTool.extraMoves}),
        throwsA(isA<DatabaseException>()),
      );
      expect(c.data.toJson(), before);
      expect((await repo.load()).toJson(), before);
      await db.execute('DROP TRIGGER reject_flow_tool');
      await c.startFlow(level);
      before = c.data.toJson();
      await db.execute(
        "CREATE TRIGGER reject_flow_tool BEFORE INSERT ON settings WHEN NEW.key='finora_world' BEGIN SELECT RAISE(ABORT,'tool write failure'); END",
      );
      await expectLater(
        c.useFlowTool(
          level,
          c.data.world.flow.session!,
          FlowTool.hammer,
          cell: 0,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(c.data.toJson(), before);
      expect((await repo.load()).toJson(), before);
      await db.execute('DROP TRIGGER reject_flow_tool');
      await c.useFlowTool(
        level,
        c.data.world.flow.session!,
        FlowTool.hammer,
        cell: 0,
      );
      expect(c.data.world.flow.available(FlowTool.hammer), 1);
    });

    test(
      'target validation and double taps cannot waste stock or moves',
      () async {
        await c.startFlow(level);
        var state = c.data.world.flow.session!;
        final invalid = await c.useFlowTool(
          level,
          state,
          FlowTool.hammer,
          cell: -1,
        );
        expect(invalid.accepted, isFalse);
        expect(c.data.world.flow.available(FlowTool.hammer), 2);
        state = c.data.world.flow.session!;
        final first = c.useFlowTool(level, state, FlowTool.hammer, cell: 0);
        final duplicate = c.useFlowTool(level, state, FlowTool.hammer, cell: 0);
        await expectLater(duplicate, throwsFormatException);
        await first;
        expect(c.data.world.flow.available(FlowTool.hammer), 1);
        expect(c.data.world.flow.session!.remainingMoves, state.remainingMoves);
        FlowEngine.validateSession(level, c.data.world.flow.session!);
      },
    );

    test(
      'old JSON import cannot refill consumed tools; full CSV retains ledger',
      () async {
        final stale = await repo.exportJson();
        await c.startFlow(level);
        await c.useFlowTool(
          level,
          c.data.world.flow.session!,
          FlowTool.hammer,
          cell: 0,
        );
        final state = c.data.world.flow.session!.toJson();
        await c.importJson(stale);
        expect(c.data.world.flow.available(FlowTool.hammer), 1);
        expect(c.data.world.flow.session!.toJson(), state);
        final other = await FinanceRepository.open(
          factory: databaseFactoryFfi,
          path: '${dir.path}/copy',
        );
        try {
          await other.importCsv(await repo.exportFullCsv());
          expect((await other.load()).world.flow.spent[FlowTool.hammer], 1);
        } finally {
          await other.close();
        }
      },
    );

    test(
      'a lost attempt resumes once with the same field and no duplicated reward',
      () async {
        // A legitimate stable snapshot of the same level after all its moves.
        final initial = FlowEngine.newGame(level);
        final lost = FlowSession(
          levelId: level.id,
          board: initial.board,
          remainingMoves: 0,
          score: 0,
          progress: {},
          rngState: initial.rngState,
          status: FlowStatus.lost,
        );
        FlowEngine.validateSession(level, lost);
        await repo.save(
          c.data.copyWith(
            world: c.data.world.copyWith(
              flow: c.data.world.flow.copyWith(session: lost),
            ),
          ),
        );
        await restart();
        final before = c.data.world.flow.session!;
        final rewards = Map.of(c.data.world.rewards);
        final first = c.useFlowTool(level, before, FlowTool.extraMoves);
        final repeated = c.useFlowTool(level, before, FlowTool.extraMoves);
        await expectLater(repeated, throwsFormatException);
        await first;
        final active = c.data.world.flow.session!;
        expect(active.status, FlowStatus.active);
        expect(active.remainingMoves, 5);
        expect(
          active.board.map((c) => c.toJson()).toList(),
          before.board.map((c) => c.toJson()).toList(),
        );
        expect(active.score, before.score);
        expect(active.rngState, before.rngState);
        expect(active.progress, before.progress);
        expect(c.data.world.rewards, rewards);
        expect(c.data.world.flow.available(FlowTool.extraMoves), 0);
        await expectLater(
          c.useFlowTool(level, active, FlowTool.extraMoves),
          throwsFormatException,
        );
        await restart();
        expect(c.data.world.flow.session!.remainingMoves, 5);
      },
    );

    test('board specials never spend consumable bomb inventory', () async {
      final replay =
          (jsonDecode(
                    File('assets/flow/winning_replays.json').readAsStringSync(),
                  )
                  as Map)['levels']
              as List;
      final sequence = (replay.first as Map)['moves'] as List;
      await c.startFlow(level);
      for (final pair in sequence) {
        await c.swapFlow(
          level,
          c.data.world.flow.session!,
          pair[0] as int,
          pair[1] as int,
        );
      }
      expect(c.data.world.flow.session!.status, FlowStatus.won);
      expect(c.data.world.flow.spent, isEmpty);
      expect(c.data.world.flow.available(FlowTool.bomb), 1);
    });
  });
}
