import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/main.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Quiet extends NotificationService {
  @override
  Future<void> sync(FinanceData data) async {}
}

Future<void> fonts() async {
  const dir = '/opt/tools/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular', 'Roboto-Medium', 'Roboto-Bold']) {
    roboto.addFont(
      Future.value(ByteData.sublistView(File('$dir/$f.ttf').readAsBytesSync())),
    );
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons');
  icons.addFont(
    Future.value(
      ByteData.sublistView(
        File('$dir/MaterialIcons-Regular.otf').readAsBytesSync(),
      ),
    ),
  );
  await icons.load();
}

void main() {
  const accent = String.fromEnvironment('ACCENT', defaultValue: 'harbor');
  const mode = String.fromEnvironment('MODE', defaultValue: 'light');
  const out = String.fromEnvironment('OUT', defaultValue: '/tmp/p.png');
  testWidgets('preview', (tester) async {
    await initializeDateFormatting('ru');
    sqfliteFfiInit();
    late FinanceController c;
    late Directory temp;
    late FinanceRepository repo;
    await tester.runAsync(() async {
      await fonts();
      temp = await Directory.systemTemp.createTemp('prev');
      repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/db',
      );
      final demo = createDemoData(DateTime.now());
      await repo.save(
        demo.copyWith(
          preferences: demo.preferences.copyWith(
            theme: mode,
            accent: accent,
            onboarded: true,
            tips: false,
          ),
        ),
      );
      c = FinanceController(repo, _Quiet(), await repo.load());
    });
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('shot'),
        child: FinoraApp(controller: c, requireDeviceSecurity: false),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    const tab = String.fromEnvironment('TAB', defaultValue: '');
    if (tab.isNotEmpty) {
      await tester.tap(find.text(tab).last);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('shot')),
    );
    await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ImageByteFormat.png);
      File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      c.dispose();
      await repo.close();
    });
  });
}
