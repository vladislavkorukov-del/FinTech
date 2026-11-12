import 'dart:io';

import 'package:flutter/services.dart';

/// Widget tests normally replace fonts with Ahem squares. Screenshots explicitly
/// load the SDK's Android fonts and the app's bundled Inter.
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
  // The app's own face (pubspec «Inter»), read from the bundled assets.
  final inter = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(
      File(
        'assets/fonts/inter/Inter-$weight.ttf',
      ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await Future.wait([text.load(), icons.load(), inter.load()]);
}
