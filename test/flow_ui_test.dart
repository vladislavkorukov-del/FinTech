import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/flow/flow.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/world/finora_world_screen.dart';
import 'package:finora/presentation/screens/world/flow_game_screen.dart';
import 'package:finora/presentation/screens/world/flow_screens.dart';
import 'package:finora/presentation/screens/world/world_games_screen.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/notification_service.dart';
import 'package:finora/services/flow_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/screenshot_fonts.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late FinanceRepository repo;
  late FinanceController c;
  late List<FlowLevel> levels;
  late List<(int, int)> proof;
  late List<(int, int)> secondProof;
  setUp(() async {
    await initializeDateFormatting('ru');
    levels = FlowLevels.decode(
      File('assets/flow/levels.json').readAsStringSync(),
    );
    final first =
        (jsonDecode(File('assets/flow/winning_replays.json').readAsStringSync())
                as Map)['levels'][0]
            as Map;
    proof = (first['moves'] as List)
        .map((v) => ((v as List)[0] as int, v[1] as int))
        .toList();
    final second =
        (jsonDecode(File('assets/flow/winning_replays.json').readAsStringSync())
                as Map)['levels'][1]
            as Map;
    secondProof = (second['moves'] as List)
        .map((v) => ((v as List)[0] as int, v[1] as int))
        .toList();
    dir = await Directory.systemTemp.createTemp('finora-flow-ui-');
    repo = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/db',
    );
    await repo.save(
      const FinanceData(
        accounts: [Account(id: 'a', name: 'Карта', openingMinor: 100000)],
        members: [Member(id: 'me', name: 'Я')],
      ),
    );
    c = FinanceController(repo, _Quiet(), await repo.load());
    await c.syncWorld();
  });
  tearDown(() async {
    c.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (Platform.environment.containsKey('FINORA_FLOW_CAPTURE_DIR')) {
      await tester.runAsync(loadScreenshotFonts);
    }
    await tester.runAsync(FlowCatalog.load);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark, 'coffee'),
          builder: (context, child) => RepaintBoundary(
            key: const ValueKey('flow-capture'),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
          ),
          home: screen,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> wait(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 150 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
    expect(condition(), isTrue);
    await tester.pumpAndSettle();
  }

  Future<void> touch(WidgetTester tester, Finder target) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(target, 200, maxScrolls: 30);
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> play(
    WidgetTester tester, {
    bool doubleTap = false,
    List<(int, int)>? sequence,
  }) async {
    for (final move in sequence ?? proof) {
      final before = c.data.world.flow.session!.remainingMoves;
      await touch(tester, find.byKey(ValueKey('flow-cell-${move.$1}')));
      await touch(tester, find.byKey(ValueKey('flow-cell-${move.$2}')));
      if (doubleTap) {
        await tester.tap(
          find.byKey(ValueKey('flow-cell-${move.$2}')),
          warnIfMissed: false,
        );
      }
      await wait(
        tester,
        () => c.data.world.flow.session!.remainingMoves == before - 1,
      );
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['FINORA_FLOW_CAPTURE_DIR'];
    if (output == null) return;
    final context = tester.element(find.byKey(const ValueKey('flow-capture')));
    final providers = tester
        .widgetList<Image>(find.byType(Image))
        .map((w) => w.image)
        .toSet();
    await tester.runAsync(
      () => Future.wait(providers.map((p) => precacheImage(p, context))),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('flow-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'real world entry, map, preparation, touch victory, repeat and exit work',
    (tester) async {
      await mount(tester, const FinoraWorldScreen());
      await touch(tester, find.byKey(const ValueKey('world-destination-5')));
      await tester.pumpAndSettle();
      expect(find.byType(WorldGamesScreen), findsOneWidget);
      await touch(tester, find.byKey(const ValueKey('world-game-flow')));
      await wait(
        tester,
        () => find.byKey(const ValueKey('flow-level-1')).evaluate().isNotEmpty,
      );
      await capture(tester, 'map');
      final locked = tester.widget<ListTile>(
        find.byKey(const ValueKey('flow-level-2')),
      );
      expect(locked.enabled, isFalse);
      await touch(tester, find.byKey(const ValueKey('flow-level-1')));
      await capture(tester, 'preparation');
      await touch(tester, find.byKey(const ValueKey('flow-start')));
      await wait(
        tester,
        () => find.byKey(const ValueKey('flow-board')).evaluate().isNotEmpty,
      );
      await play(tester, doubleTap: true);
      expect(find.byKey(const ValueKey('flow-result')), findsOneWidget);
      expect(c.data.world.flow.results[1]!.stars, greaterThanOrEqualTo(1));
      expect(c.data.world.flow.isUnlocked(2), isTrue);
      final sparks = c.data.world.sparks;
      await capture(tester, 'victory');
      await touch(tester, find.byKey(const ValueKey('flow-replay')));
      await wait(
        tester,
        () => c.data.world.flow.session!.status == FlowStatus.active,
      );
      await play(tester);
      expect(c.data.world.sparks, sparks);
      await touch(tester, find.byKey(const ValueKey('flow-next')));
      expect(find.byType(FlowPreparationScreen), findsOneWidget);
      await touch(tester, find.byKey(const ValueKey('flow-start')));
      await wait(
        tester,
        () =>
            c.data.world.flow.session?.levelId == 2 &&
            c.data.world.flow.session?.status == FlowStatus.active,
      );
      await play(tester, sequence: secondProof);
      expect(c.data.world.flow.results, contains(2));
      await touch(tester, find.byKey(const ValueKey('flow-exit-world')));
      await tester.pumpAndSettle();
      expect(find.byType(FinoraWorldScreen), findsOneWidget);
      expect(find.byType(WorldGamesScreen), findsNothing);
      expect(c.balance, 100000);
      expect(c.data.entries, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('pause and actual SQLite reopen retain stable board and RNG', (
    tester,
  ) async {
    await tester.runAsync(() => c.startFlow(levels.first));
    await mount(tester, FlowGameScreen(level: levels.first, levels: levels));
    final move = proof.first;
    final from = find.byKey(ValueKey('flow-cell-${move.$1}'));
    final to = find.byKey(ValueKey('flow-cell-${move.$2}'));
    await tester.ensureVisible(from);
    await tester.pumpAndSettle();
    await tester.drag(from, tester.getCenter(to) - tester.getCenter(from));
    await tester.pump();
    await wait(
      tester,
      () => c.data.world.flow.session!.remainingMoves == levels.first.moves - 1,
    );
    final state = c.data.world.flow.session!.toJson();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(hours: 1));
    expect(c.data.world.flow.session!.toJson(), state);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      c.dispose();
      await repo.close();
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/db',
      );
      c = FinanceController(repo, _Quiet(), await repo.load());
    });
    await mount(tester, const FlowMapScreen());
    await wait(
      tester,
      () => find.byKey(const ValueKey('flow-resume')).evaluate().isNotEmpty,
    );
    await touch(tester, find.byKey(const ValueKey('flow-resume')));
    await tester.pumpAndSettle();
    expect(c.data.world.flow.session!.toJson(), state);
    expect(find.byKey(const ValueKey('flow-board')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('active board fits narrow phone and landscape at large text', (
    tester,
  ) async {
    await tester.runAsync(() => c.startFlow(levels.first));
    for (final size in [const Size(320, 640), const Size(740, 360)]) {
      await mount(
        tester,
        FlowGameScreen(level: levels.first, levels: levels),
        size: size,
        scale: 1.6,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('flow-board')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await mount(tester, FlowGameScreen(level: levels.first, levels: levels));
    await capture(tester, 'board');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'defeat on last move keeps next locked and offers a working replay',
    (tester) async {
      final json = levels.first.toJson()
        ..['moves'] = 1
        ..['goals'] = [
          {'key': 'collect:coin', 'target': 9999},
        ];
      final level = FlowLevel.fromJson(Map<String, dynamic>.from(json));
      await tester.runAsync(() => c.startFlow(level, restart: true));
      await mount(tester, FlowGameScreen(level: level, levels: [level]));
      await touch(tester, find.byKey(ValueKey('flow-cell-${proof.first.$1}')));
      await touch(tester, find.byKey(ValueKey('flow-cell-${proof.first.$2}')));
      await wait(
        tester,
        () => c.data.world.flow.session!.status == FlowStatus.lost,
      );
      expect(find.text('Ходы закончились'), findsOneWidget);
      expect(find.byKey(const ValueKey('flow-next')), findsNothing);
      expect(c.data.world.flow.isUnlocked(2), isFalse);
      await capture(tester, 'defeat');
      await touch(tester, find.byKey(const ValueKey('flow-replay')));
      await wait(
        tester,
        () => c.data.world.flow.session!.status == FlowStatus.active,
      );
      expect(c.data.world.flow.session!.remainingMoves, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
