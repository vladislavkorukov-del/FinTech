import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens a main place through the side panel (Release navigation): the
/// menu button, then the place by its label.
Future<void> openPlace(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('nav-menu')).first);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('app-drawer')),
      matching: find.text(label),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Starts voice input from the side panel («Полезное» → «Голосовой ввод»).
Future<void> startVoice(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-menu')).first);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  await tester.tap(find.byKey(const ValueKey('drawer-voice')));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}
