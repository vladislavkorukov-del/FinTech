import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/motion.dart';
import 'package:finora/presentation/widgets/voice_orb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finance 1.20: the living voice orb replaces «+» in the bottom bar.
void main() {
  Future<(int, int)> mount(WidgetTester tester) async {
    var taps = 0, holds = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.app(Brightness.dark, 'midnight'),
        home: Scaffold(
          body: Center(
            child: VoiceOrb(onTap: () => taps++, onLongPress: () => holds++),
          ),
        ),
      ),
    );
    await tester.pump();
    final orb = find.byKey(const ValueKey('nav-voice'));
    await tester.tap(orb);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.longPress(orb);
    await tester.pump(const Duration(milliseconds: 200));
    return (taps, holds);
  }

  testWidgets('tap is voice, long press is a manual entry', (tester) async {
    final (taps, holds) = await mount(tester);
    expect(taps, 1);
    expect(holds, 1);
    expect(find.bySemanticsLabel('Голосовой ввод операции'), findsOneWidget);
    // Still in tests and with reduce motion: no animation at all.
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('it moves while used and rests when idle', (tester) async {
    Motion.debugForceAmbient = true;
    addTearDown(() => Motion.debugForceAmbient = false);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.app(Brightness.dark, 'midnight'),
        home: Scaffold(
          body: Center(
            child: VoiceOrb(onTap: () {}, onLongPress: () {}),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isTrue);
    // Ten seconds without touches, then it finishes its loop and stops.
    await tester.pump(VoiceOrb.idle);
    await tester.pump(const Duration(seconds: 8));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    // A touch anywhere wakes it.
    VoiceOrb.activity.value++;
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(VoiceOrb.idle);
    await tester.pump(const Duration(seconds: 8));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
