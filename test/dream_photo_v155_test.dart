import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/presentation/widgets/dream_photo.dart';
import 'package:finora/presentation/widgets/photo_cropper.dart';
import 'package:finora/services/goal_photo_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 1.55: a photo on a dream's card, cropped to the card's 2:1 shape.
void main() {
  sqfliteFfiInit();

  Future<Uint8List> png(int width, int height, Color color) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = color,
    );
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  test('crop rect and clamping keep the frame covered', () {
    const frame = Size(300, 150);
    // A 1000×1000 photo covering the frame at 0.3, shifted to its middle.
    final rect = PhotoCropScreen.cropRect(
      frame: frame,
      scale: .3,
      offset: const Offset(0, -75),
    );
    expect(rect.left, 0);
    expect(rect.top, closeTo(250, 1e-9));
    expect(rect.width, closeTo(1000, 1e-9));
    expect(rect.height, closeTo(500, 1e-9));
    // Dragging past an edge stops at the edge.
    final clamped = PhotoCropScreen.clampOffset(
      frame: frame,
      image: const Size(1000, 1000),
      scale: .3,
      offset: const Offset(40, -900),
    );
    expect(clamped, const Offset(0, -150));
  });

  testWidgets('render returns a 2:1 PNG of the framed part', (tester) async {
    await tester.runAsync(() async {
      final bytes = await png(800, 800, const Color(0xFF3FE0C2));
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      final out = await PhotoCropScreen.render(
        image,
        const Rect.fromLTWH(0, 200, 800, 400),
        aspect: 2,
        maxWidth: 600,
      );
      final decoded = await (await ui.instantiateImageCodec(
        out,
      )).getNextFrame();
      expect(decoded.image.width, 600);
      expect(decoded.image.height, 300);
      image.dispose();
      decoded.image.dispose();
    });
  });

  testWidgets('the crop screen returns the photo on «Готово»', (tester) async {
    final bytes = (await tester.runAsync(
      () => png(640, 480, const Color(0xFFFF7FB0)),
    ))!;
    Uint8List? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await Navigator.push<Uint8List>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PhotoCropScreen(bytes: bytes),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Decoding is real asynchronous work.
    for (var i = 0; i < 20 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byType(RawImage), findsOneWidget);
    // A pinch-free drag moves the photo but never off the frame.
    await tester.drag(
      find.byKey(const ValueKey('photo-crop-area')),
      const Offset(-500, 0),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('photo-crop-done')));
    for (var i = 0; i < 20 && result == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    final size = (await tester.runAsync(() async {
      final frame = await (await ui.instantiateImageCodec(
        result!,
      )).getNextFrame();
      final s = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      return s;
    }))!;
    expect(size.width / size.height, closeTo(2, .01));
  });

  test(
    'photo path survives the database, an upgrade from 1.54 and JSON',
    () async {
      final dir = await Directory.systemTemp.createTemp('finora-dream-');
      addTearDown(() => dir.delete(recursive: true));
      // A 1.54 database (schema 5, no photo column) is upgraded on open.
      final dbPath = '${dir.path}/finora.db';
      await (await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: dbPath,
      )).close();
      final raw = await databaseFactoryFfi.openDatabase(dbPath);
      await raw.execute('ALTER TABLE goals DROP COLUMN photoPath');
      await raw.execute('PRAGMA user_version = 5');
      await raw.close();
      final repository = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: dbPath,
      );
      addTearDown(repository.close);
      final store = GoalPhotoStore(root: dir);
      final photo = await store.save(
        (await png(400, 200, const Color(0xFF3FE0C2))),
      );
      expect(photo, contains('goal_photos'));
      var data = await repository.load();
      data = data.copyWith(
        goals: [
          Goal(id: 'sea', name: 'Море', targetMinor: 100000, photoPath: photo),
        ],
        entries: const [],
        recurring: const [],
        budgets: const [],
      );
      await repository.save(data);
      expect((await repository.load()).goals.single.photoPath, photo);

      // The JSON copy carries the image itself, never the device path.
      final json = await repository.exportJson();
      final envelope = jsonDecode(json) as Map<String, dynamic>;
      expect(json, isNot(contains(photo)));
      expect((envelope['goalPhotos'] as Map).keys, ['sea']);
      await repository.save(
        data.copyWith(goals: [data.goals.single.copyWith(photoPath: null)]),
      );
      await repository.importJson(json);
      final restored = (await repository.load()).goals.single.photoPath!;
      expect(File(restored).existsSync(), isTrue);
      expect(
        await File(restored).readAsBytes(),
        await File(photo).readAsBytes(),
      );

      // Deleting through the store only touches its own folder.
      final outside = File('${dir.path}/keep.txt')..writeAsStringSync('x');
      await store.delete(outside.path);
      expect(outside.existsSync(), isTrue);
      await store.delete(photo);
      expect(File(photo).existsSync(), isFalse);
    },
  );

  testWidgets('a dream with a photo shows it behind readable white text', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('finora-dream-ui-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/dream.png');
    await tester.runAsync(
      () async =>
          file.writeAsBytes(await png(200, 100, const Color(0xFF204060))),
    );
    expect(hasDreamPhoto(file.path), isTrue);
    expect(hasDreamPhoto('${dir.path}/missing.png'), isFalse);
    expect(hasDreamPhoto(null), isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DreamPhotoCard(
            path: file.path,
            onTap: () {},
            child: const Text('Путешествие'),
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    final text = tester.widget<RichText>(
      find.descendant(
        of: find.byType(DreamPhotoCard),
        matching: find.byType(RichText),
      ),
    );
    expect(text.text.style?.color, Colors.white);
  });
}
