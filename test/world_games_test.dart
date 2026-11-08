import 'dart:io';

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/world_games.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/world/world_games_screen.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  test('only supported finite game keys are accepted', () {
    for (final kind in WorldGames.kinds) {
      for (var level = 0; level < 3; level++) {
        expect(WorldGames.validKey('$kind:$level'), isTrue);
        expect(WorldGames.validate('$kind:$level', []), isTrue);
        expect(WorldGames.complete('$kind:$level', []), isFalse);
      }
    }
    for (final invalid in [
      'parcel:3',
      'parcel:-1',
      'parcel:00',
      '',
      'roulette:0',
    ]) {
      expect(WorldGames.validate(invalid, []), isFalse);
      expect(WorldGames.complete(invalid, []), isFalse);
    }
  });

  test('constellations require their exact pattern and legal prefixes', () {
    for (var level = 0; level < 3; level++) {
      final key = 'constellation:$level',
          pattern = constellations[level].pattern;
      for (var i = 0; i < pattern.length; i++) {
        expect(WorldGames.validate(key, pattern.take(i).toList()), isTrue);
        expect(WorldGames.complete(key, pattern.take(i).toList()), isFalse);
      }
      expect(WorldGames.complete(key, pattern), isTrue);
      expect(WorldGames.validate(key, [...pattern, 0]), isFalse);
      expect(WorldGames.validate(key, [-1]), isFalse);
      final wrong = [...pattern]..[0] = (pattern.first + 1) % pattern.length;
      expect(WorldGames.complete(key, wrong), isFalse);
    }
  });

  test(
    'parcel placements reject overlap, wrapping, duplicates and bad indices',
    () {
      expect(WorldGames.complete('parcel:0', [0, 102, 206]), isTrue);
      expect(WorldGames.complete('parcel:1', [0, 106, 202]), isTrue);
      expect(WorldGames.complete('parcel:2', [4, 100, 201]), isTrue);
      expect(WorldGames.validate('parcel:0', [0, 100]), isFalse);
      expect(
        WorldGames.validate('parcel:0', [2]),
        isFalse,
      ); // Square wraps edge.
      expect(WorldGames.validate('parcel:0', [0, 0]), isFalse);
      expect(WorldGames.validate('parcel:0', [300]), isFalse);
      expect(WorldGames.validate('parcel:0', [-1]), isFalse);
      expect(WorldGames.validate('parcel:0', [9]), isFalse);
      expect(WorldGames.validate('parcel:0', [0, 102]), isTrue);
      expect(WorldGames.complete('parcel:0', [0, 102]), isFalse);
    },
  );

  test('all expedition branches finish after exactly three valid choices', () {
    for (var route = 0; route < 3; route++) {
      for (var a = 0; a < 3; a++) {
        for (var b = 0; b < 3; b++) {
          for (var c = 0; c < 3; c++) {
            expect(WorldGames.complete('expedition:$route', [a, b, c]), isTrue);
            expect(expeditions[route].result([a, b, c]), isNotEmpty);
          }
        }
      }
      expect(WorldGames.complete('expedition:$route', [0, 1]), isFalse);
      expect(WorldGames.validate('expedition:$route', [0, 1, 3]), isFalse);
      expect(WorldGames.validate('expedition:$route', [0, 1, 2, 0]), isFalse);
    }
  });

  testWidgets(
    'all activities complete through touch, persist and replay without extra rewards',
    (tester) async {
      sqfliteFfiInit();
      final temp = await tester.runAsync(
        () => Directory.systemTemp.createTemp('finora-world-games-'),
      );
      final repo = await tester.runAsync(
        () => FinanceRepository.open(
          factory: databaseFactoryFfi,
          path: '${temp!.path}/db',
        ),
      );
      await tester.runAsync(
        () => repo!.save(
          const FinanceData(
            members: [Member(id: 'me', name: 'Я')],
          ),
        ),
      );
      final loaded = await tester.runAsync(repo!.load);
      final c = FinanceController(repo, _Quiet(), loaded!);
      addTearDown(() async {
        c.dispose();
        await repo.close();
        await temp!.delete(recursive: true);
      });
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        FinanceScope(
          controller: c,
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark, 'coffee'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: const WorldGamesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> show(Finder finder) async {
        await tester.scrollUntilVisible(finder, 180, maxScrolls: 40);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
      }

      Future<void> ready(bool Function() done) async {
        for (var i = 0; i < 100 && !done(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 25));
        }
        expect(done(), isTrue);
        await tester.pumpAndSettle();
      }

      Future<void> launch(String key) async {
        final button = find.byKey(ValueKey('world-game-$key'));
        await show(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      Future<void> click(Finder button) async {
        await show(button);
        await tester.tap(button);
        await tester.pump();
      }

      await launch('constellation:0');
      for (final star in constellations[0].pattern) {
        final n = (c.data.world.games['constellation:0'] ?? []).length;
        await click(find.byKey(ValueKey('world-star-$star')));
        await ready(
          () => c.data.world.games['constellation:0']?.length == n + 1,
        );
      }
      await show(find.byKey(const ValueKey('world-game-result')));
      expect(c.data.world.rewards.containsKey('game:constellation:0'), isTrue);
      final sparks = c.data.world.sparks;
      await click(find.byKey(const ValueKey('world-game-replay')));
      await ready(() => c.data.world.games['constellation:0']!.isEmpty);
      expect(c.data.world.sparks, sparks);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await launch('parcel:0');
      for (final (piece, cell) in [(0, 0), (1, 2), (2, 6)]) {
        final n = (c.data.world.games['parcel:0'] ?? []).length;
        if (piece != 0) {
          await click(find.byKey(ValueKey('world-parcel-piece-$piece')));
          await tester.pumpAndSettle();
        }
        await click(find.byKey(ValueKey('world-parcel-cell-$cell')));
        await ready(() => c.data.world.games['parcel:0']?.length == n + 1);
      }
      await show(find.byKey(const ValueKey('world-game-result')));
      expect(c.data.world.rewards.containsKey('game:parcel:0'), isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await launch('expedition:0');
      for (var i = 0; i < 3; i++) {
        await click(find.byKey(const ValueKey('world-expedition-choice-1')));
        await ready(() => c.data.world.games['expedition:0']?.length == i + 1);
      }
      await show(find.byKey(const ValueKey('world-game-result')));
      expect(c.data.world.rewards.containsKey('game:expedition:0'), isTrue);
      final disk = await tester.runAsync(repo.load);
      expect(disk!.world.games['expedition:0'], [1, 1, 1]);
      expect(disk.world.games['parcel:0'], [0, 102, 206]);
      expect(
        disk.world.rewards.keys,
        containsAll([
          'game:constellation:0',
          'game:parcel:0',
          'game:expedition:0',
        ]),
      );
      expect(disk.entries, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
