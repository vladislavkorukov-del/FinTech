import 'package:finora/services/receipt_share_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('finora/receipt_share');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ReceiptShareService service;

  Future<void> nativeEvent(String method) async {
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method)),
      (_) {},
    );
  }

  setUp(() {
    service = ReceiptShareService();
  });
  tearDown(() async {
    await service.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'optional share target is a no-op on a host without native plugin',
    () async {
      expect(await service.takePendingImage(), isNull);
    },
  );

  test(
    'takes cold-start private copy exactly once with no URI data sent back',
    () async {
      String? pending =
          '/data/user/0/com.finora.fintech/cache/receipt_shares/uuid.jpg';
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final result = pending;
        pending = null;
        return result;
      });
      expect(await service.takePendingImage(), endsWith('/uuid.jpg'));
      expect(await service.takePendingImage(), isNull);
      expect(calls.map((call) => call.method), [
        'takeSharedImage',
        'takeSharedImage',
      ]);
      expect(calls.every((call) => call.arguments == null), isTrue);
    },
  );

  test('warm intent event signals UI to consume pending image', () async {
    final signal = expectLater(service.imageAvailable, emits(null));
    await nativeEvent('imageAvailable');
    await signal;
  });

  test(
    'share error signals consumption, take preserves actionable error',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'SHARE_IMAGE_TOO_LARGE',
          message: '/private/secret',
        );
      });
      final signal = expectLater(service.imageAvailable, emits(null));
      await nativeEvent('shareError');
      await signal;
      await expectLater(
        service.takePendingImage(),
        throwsA(
          isA<ReceiptShareException>()
              .having((e) => e.code, 'code', 'SHARE_IMAGE_TOO_LARGE')
              .having(
                (e) => e.message,
                'message',
                allOf(contains('20'), isNot(contains('secret'))),
              ),
        ),
      );
    },
  );

  test('rejects native URI, relative or nonstring output', () async {
    for (final response in [
      'content://media/42',
      'file:///sdcard/a.jpg',
      'relative.jpg',
      42,
      '/a\u0000.jpg',
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      await expectLater(
        service.takePendingImage(),
        throwsA(
          isA<ReceiptShareException>().having(
            (e) => e.code,
            'code',
            'SHARE_INVALID_RESPONSE',
          ),
        ),
      );
    }
  });

  test('unknown native events do not open image entry flow', () async {
    final seen = <void>[];
    final subscription = service.imageAvailable.listen(seen.add);
    await nativeEvent('unknown');
    await Future<void>.delayed(Duration.zero);
    expect(seen, isEmpty);
    await subscription.cancel();
  });

  test(
    'disposing detaches delivery and suppresses later native intake',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return '/private/a.jpg';
      });
      await service.dispose();
      await service.dispose();
      expect(await service.takePendingImage(), isNull);
      expect(calls, 0);
      await expectLater(service.imageAvailable, emitsDone);
    },
  );

  test(
    'permission/provider failure is an explicit error, not empty pending data',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'SHARE_FAILED', details: 'bank text');
      });
      await expectLater(
        service.takePendingImage(),
        throwsA(
          isA<ReceiptShareException>()
              .having((e) => e.code, 'code', 'SHARE_FAILED')
              .having(
                (e) => e.toString(),
                'message',
                isNot(contains('bank text')),
              ),
        ),
      );
    },
  );
}
