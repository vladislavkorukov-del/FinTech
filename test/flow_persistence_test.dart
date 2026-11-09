import 'dart:convert';
import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/finora_world.dart';
import 'package:finora/domain/flow/flow.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/wardrobe.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  sqfliteFfiInit();
  final now = DateTime(2026, 11, 8, 12);
  late Directory temp;
  late FinanceRepository repo;
  late FinanceController c;
  late List<FlowLevel> levels;
  late List<Map<String, dynamic>> replays;
  String path() => '${temp.path}/ledger.db';
  setUp(() async {
    levels = FlowLevels.decode(
      File('assets/flow/levels.json').readAsStringSync(),
    );
    replays =
        ((jsonDecode(
                      File(
                        'assets/flow/winning_replays.json',
                      ).readAsStringSync(),
                    )
                    as Map)['levels']
                as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    temp = await Directory.systemTemp.createTemp('finora-flow-persistence-');
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: path(),
    );
    await repo.save(
      FinanceData(
        accounts: const [
          Account(id: 'a', name: 'Основная карта', openingMinor: 100000),
        ],
        members: const [Member(id: 'me', name: 'Я')],
        wardrobe: WardrobeState(
          received: {'moon_cat': now, 'frost_queen': now},
          equipped: const {
            WardrobeSlot.companion: 'moon_cat',
            WardrobeSlot.cape: 'frost_queen',
          },
        ),
      ),
    );
    c = FinanceController(repo, _Quiet(), await repo.load())
      ..achievementClock = () => now;
    // Settle the existing account achievements before measuring game effects.
    await c.syncWorld();
  });
  tearDown(() async {
    c.dispose();
    await repo.close();
    await temp.delete(recursive: true);
  });
  Future<void> restart() async {
    c.dispose();
    await repo.close();
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: path(),
    );
    c = FinanceController(repo, _Quiet(), await repo.load())
      ..achievementClock = () => now;
  }

  List<(int, int)> moves(int id) =>
      (replays.firstWhere((r) => r['levelId'] == id)['moves'] as List)
          .map((m) => ((m as List)[0] as int, m[1] as int))
          .toList();

  test(
    'all20 playable levels persist every stable move, unlock and reward once',
    () async {
      final financial = c.data.toJson()
        ..remove('world')
        ..remove('achievements')
        ..remove('wardrobe');
      final wardrobe = c.data.wardrobe.toJson();
      final balance = c.balance;
      for (final level in levels) {
        expect(c.data.world.flow.isUnlocked(level.id), isTrue);
        await c.startFlow(level, restart: true);
        final sequence = moves(level.id);
        for (var step = 0; step < sequence.length; step++) {
          final before = c.data.world.flow.session!;
          final turn = await c.swapFlow(
            level,
            before,
            sequence[step].$1,
            sequence[step].$2,
          );
          expect(turn.accepted, isTrue, reason: 'level${level.id},step$step');
          final snapshot = turn.session.toJson();
          await restart();
          expect(c.data.world.flow.session!.toJson(), snapshot);
          FlowEngine.validateSession(level, c.data.world.flow.session!);
        }
        final state = c.data.world.flow.session!;
        expect(state.status, FlowStatus.won);
        expect(
          level.goals.every((g) => (state.progress[g.key] ?? 0) >= g.target),
          isTrue,
        );
        expect(
          c.data.world.flow.results[level.id]!.stars,
          inInclusiveRange(1, 3),
        );
        expect(c.data.world.rewards, contains('flow:level:${level.id}:v1'));
      }
      expect(c.data.world.flow.results.length, 20);
      expect(
        c.data.world.rewards.keys.where((k) => k.startsWith('flow:')).length,
        20,
      );
      expect(c.balance, balance);
      expect(c.data.entries, isEmpty);
      expect(c.data.wardrobe.toJson(), wardrobe);
      expect(
        c.data.toJson()
          ..remove('world')
          ..remove('achievements')
          ..remove('wardrobe'),
        financial,
      );
      final rewards = c.data.world.rewards.length;
      final sparks = c.data.world.sparks;
      await c.startFlow(levels.first, restart: true);
      for (final move in moves(1)) {
        await c.swapFlow(
          levels.first,
          c.data.world.flow.session!,
          move.$1,
          move.$2,
        );
      }
      expect(c.data.world.rewards.length, rewards);
      expect(c.data.world.sparks, sparks);
    },
  );

  test(
    'locked levels and queued stale touches cannot consume extra moves',
    () async {
      await expectLater(c.startFlow(levels[1]), throwsFormatException);
      await c.startFlow(levels.first);
      final session = c.data.world.flow.session!;
      final turn = await c.swapFlow(levels.first, session, 0, 63);
      expect(turn.accepted, isFalse);
      expect(c.data.world.flow.session!.toJson(), session.toJson());
      final move = moves(1).first;
      final first = c.swapFlow(levels.first, session, move.$1, move.$2);
      final stale = c.swapFlow(levels.first, session, move.$1, move.$2);
      await expectLater(stale, throwsFormatException);
      await first;
      expect(
        c.data.world.flow.session!.remainingMoves,
        session.remainingMoves - 1,
      );
      await restart();
      expect(
        c.data.world.flow.session!.remainingMoves,
        session.remainingMoves - 1,
      );
    },
  );

  test(
    'failed game commit rolls back session and first-win reward together',
    () async {
      final level = levels.first;
      await c.startFlow(level);
      final sequence = moves(1);
      for (final move in sequence.take(sequence.length - 1)) {
        await c.swapFlow(level, c.data.world.flow.session!, move.$1, move.$2);
      }
      final before = c.data.toJson();
      final db = await databaseFactoryFfi.openDatabase(path());
      await db.execute(
        "CREATE TRIGGER reject_flow BEFORE INSERT ON settings WHEN NEW.key='finora_world' BEGIN SELECT RAISE(ABORT,'flow write failure'); END",
      );
      final last = sequence.last;
      await expectLater(
        c.swapFlow(level, c.data.world.flow.session!, last.$1, last.$2),
        throwsA(isA<DatabaseException>()),
      );
      expect(c.data.toJson(), before);
      expect((await repo.load()).toJson(), before);
      await db.execute('DROP TRIGGER reject_flow');
      await c.swapFlow(level, c.data.world.flow.session!, last.$1, last.$2);
      expect(c.data.world.flow.session!.status, FlowStatus.won);
      expect(
        c.data.world.rewards.keys.where((k) => k.startsWith('flow:')).length,
        1,
      );
    },
  );

  test(
    'old world migration, malformed optional game and reward-version ledger',
    () {
      var old = WorldEngine.reward(
        const WorldState(),
        'tutorial',
        now: now,
      ).toJson();
      old.remove('flow');
      old.remove('gardenGoalId');
      old['background'] = 'pearl';
      final migrated = WorldState.fromJson(Map<String, dynamic>.from(old));
      expect(migrated.flow.session, isNull);
      expect(migrated.flow.results, isEmpty);
      expect(migrated.sparks, 20);
      expect(migrated.background, 'pearl');
      old['flow'] = {
        'version': 1,
        'results': {
          '1': {'stars': 2, 'bestScore': 1000},
        },
        'session': {'board': []},
      };
      final recovered = WorldState.fromJson(Map<String, dynamic>.from(old));
      expect(recovered.flow.results[1]!.stars, 2);
      expect(recovered.flow.session, isNull);
      expect(recovered.sparks, 20);
      expect(WorldCatalog.rewardFor('flow:level:20:v1'), isNotNull);
      expect(WorldCatalog.rewardFor('flow:level:21:v1'), isNull);
      expect(WorldCatalog.rewardFor('flow:level:1:v2'), isNull);
    },
  );

  test(
    'stale import and fullCSV preserve best progress, session RNG and selected garden',
    () async {
      await c.saveGoal(
        const Goal(id: 'trip', name: 'Поездка', targetMinor: 100000),
      );
      await c.selectWorldGardenGoal('trip');
      final stale = await repo.exportJson();
      await c.startFlow(levels.first);
      final move = moves(1).first;
      await c.swapFlow(
        levels.first,
        c.data.world.flow.session!,
        move.$1,
        move.$2,
      );
      final expected = c.data.world.flow.toJson();
      await c.importJson(stale);
      expect(c.data.world.flow.toJson(), expected);
      expect(c.data.world.gardenGoalId, 'trip');
      final csv = await repo.exportFullCsv();
      final other = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/fresh.db',
      );
      try {
        await other.importCsv(csv);
        expect((await other.load()).world.flow.toJson(), expected);
        expect((await other.load()).world.gardenGoalId, 'trip');
      } finally {
        await other.close();
      }
    },
  );
}
