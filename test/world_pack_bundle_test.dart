import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all29 working PNG originals load and decode from the actual asset bundle',
    () async {
      final index =
          jsonDecode(
                File('docs/world_pack/asset_index.json').readAsStringSync(),
              )
              as Map;
      final assets = index['assets'] as List;
      expect(assets.length, 29);
      for (final raw in assets) {
        final asset = raw as Map;
        final source = asset['file'] as String;
        final key = source.replaceFirst('assets/', 'assets/finora/world/');
        final data = await rootBundle.load(key);
        expect(data.lengthInBytes, asset['bytes'], reason: key);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        expect(codec.frameCount, 1, reason: key);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, asset['width'], reason: key);
        expect(frame.image.height, asset['height'], reason: key);
        frame.image.dispose();
        codec.dispose();
      }
    },
  );
}
