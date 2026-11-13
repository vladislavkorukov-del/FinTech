import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/flow/flow.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/world/flow_board.dart';
import 'package:finora/presentation/screens/world/flow_game_screen.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/services/flow_catalog.dart';
import 'package:finora/services/notification_service.dart';
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

/// 1.61: the board plays each move — swap, pop with sparks, falling pieces —
/// and settles; with animations on nothing is left running afterwards.
void main() {
  sqfliteFfiInit();
  late Directory dir;
  late FinanceRepository repo;
  late FinanceController c;
  late List<FlowLevel> levels;
  late List<(int, int)> proof;
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
    dir = await Directory.systemTemp.createTemp('finora-flow-motion-');
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

  testWidgets('a move is swapped, popped, refilled and settles', (
    tester,
  ) async {
    final output = Platform.environment['FINORA_FLOW_CAPTURE_DIR'];
    if (output != null) await tester.runAsync(loadScreenshotFonts);
    await tester.runAsync(FlowCatalog.load);
    await tester.runAsync(() => c.startFlow(levels.first));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FinanceScope(
        controller: c,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark, 'coffee'),
          builder: (context, child) =>
              RepaintBoundary(key: const ValueKey('cap'), child: child!),
          home: FlowGameScreen(level: levels.first, levels: levels),
        ),
      ),
    );
    Future<void> shot(String name) async {
      if (output == null) return;
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('cap')),
      );
      await tester.runAsync(() async {
        final image = await b.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File(
          '$output/motion-$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    // The board fills with falling pieces.
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.hasRunningAnimations, isTrue);
    await shot('enter');
    await tester.pump(const Duration(seconds: 1));

    final board = tester.state(find.byType(FlowBoard)) as dynamic;
    expect(board, isNotNull);
    final move = proof.first;
    final before = c.data.world.flow.session!.score;
    await tester.tap(find.byKey(ValueKey('flow-cell-${move.$1}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(ValueKey('flow-cell-${move.$2}')));
    for (var i = 0; i < 40 && c.data.world.flow.session!.score == before; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
    expect(c.data.world.flow.session!.score, greaterThan(before));
    // Swap, then the first round pops with sparks.
    await tester.pump(const Duration(milliseconds: 90));
    await shot('swap');
    await tester.pump(const Duration(milliseconds: 170));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('flow-board')),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
    await shot('pop');
    await tester.pump(const Duration(milliseconds: 200));
    await shot('fall');
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('flow-board')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // After a pause the board hints a move, then rests again.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(seconds: 2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 7));
    expect(tester.takeException(), isNull);
  });
}
