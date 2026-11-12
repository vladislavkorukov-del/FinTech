import 'package:finora/services/flow_audio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FlowAudio.channel, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FlowAudio.channel, null),
  );
  test(
    'sound follows independent setting and pause never resumes playback',
    () async {
      final audio = FlowAudio();
      await audio.configure(
        active: true,
        music: false,
        sound: true,
        haptics: false,
      );
      await audio.effect();
      expect(calls.last.method, 'effect');
      await audio.configure(
        active: false,
        music: true,
        sound: true,
        haptics: false,
      );
      final count = calls.length;
      await audio.effect(success: true);
      expect(calls, hasLength(count));
      expect(calls.last.arguments, {
        'active': false,
        'music': true,
        'sound': true,
      });
      await audio.configure(
        active: true,
        music: true,
        sound: false,
        haptics: false,
      );
      final countSilent = calls.length;
      await audio.effect();
      expect(calls, hasLength(countSilent));
      await audio.close();
      await audio.close();
      expect(calls.where((call) => call.method == 'stop'), hasLength(1));
    },
  );
  test(
    'audio failure cannot discard a committed move or throw on disposal',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            FlowAudio.channel,
            (call) async => throw PlatformException(code: 'NO_DEVICE'),
          );
      final audio = FlowAudio();
      expect(
        await audio.configure(
          active: true,
          music: true,
          sound: true,
          haptics: false,
        ),
        isFalse,
      );
      await audio.effect();
      await audio.close();
    },
  );
}
