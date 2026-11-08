import 'dart:io';

import 'package:flutter/services.dart';

/// Widget tests normally replace fonts with Ahem squares. Screenshots explicitly
/// load the SDK's Android fonts, while the app itself keeps its existing fonts.
Future<void> loadScreenshotFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    throw StateError('Set FLUTTER_ROOT to capture readable screenshots');
  }
  final folder = '$root/bin/cache/artifacts/material_fonts';
  final text = FontLoader('sans-serif');
  for (final name in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    text.addFont(
      File(
        '$folder/$name',
      ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File(
        '$folder/MaterialIcons-Regular.otf',
      ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  await Future.wait([text.load(), icons.load()]);
}
