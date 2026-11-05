import 'dart:async';

import 'package:finora/services/receipt_ocr_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('finora/ocr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ReceiptOcrService service;

  Matcher errorCode(String code) =>
      isA<ReceiptOcrException>().having((error) => error.code, 'code', code);

  setUp(() {
    service = ReceiptOcrService();
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'passes only a private path and bundled language through actual codec',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'text': 'МАГАЗИН\nTOTAL 1 250,00 ₽', 'confidence': 0.93};
      });
      final result = await service.recognize(
        '/data/user/0/com.finora.fintech/app_flutter/receipts/a.jpg',
      );
      expect(calls.single.method, 'recognize');
      expect(calls.single.arguments, {
        'path': '/data/user/0/com.finora.fintech/app_flutter/receipts/a.jpg',
        'language': 'rus+eng',
        'requestId': isA<String>(),
      });
      expect(result.text, 'МАГАЗИН\nTOTAL 1 250,00 ₽');
      expect(result.confidence, 0.93);
      expect(service.isRecognizing, isFalse);
    },
  );

  test(
    'empty text is a valid result, confidence accepts numeric zero',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'text': '', 'confidence': 0},
      );
      expect((await service.recognize('/private/blank.png')).text, isEmpty);
    },
  );

  test(
    'native visual lines survive codec and reject malformed geometry',
    () async {
      final valid = <String, Object>{
        'text': '-244,80 ₽',
        'left': .6,
        'top': .3,
        'right': .95,
        'bottom': .34,
        'confidence': .92,
      };
      Object? lines = [valid];
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'text': 'Пятёрочка -244,80 ₽',
          'confidence': .9,
          'lines': lines,
        },
      );
      final result = await service.recognize('/private/page.png');
      expect(result.lines.single.text, '-244,80 ₽');
      expect(result.lines.single.left, .6);
      expect(result.lines.single.confidence, .92);
      for (final invalid in [
        'not-lines',
        [
          {'text': 'bad'},
        ],
        [
          {...valid, 'left': -1},
        ],
        [
          {...valid, 'bottom': double.nan},
        ],
        [
          {...valid, 'top': .9},
        ],
        [
          {...valid, 'confidence': 50},
        ],
        List.filled(3001, valid),
      ]) {
        lines = invalid;
        await expectLater(
          service.recognize('/private/page.png'),
          throwsA(errorCode('OCR_INVALID_RESPONSE')),
        );
      }
    },
  );

  test(
    'rejects remote, content URI, relative and nul paths without invoking native code',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return null;
      });
      for (final path in [
        '',
        'photo.jpg',
        'https://bank.test/a.jpg',
        'content://media/42',
        'file:///a.jpg',
        '/a\u0000.jpg',
      ]) {
        await expectLater(
          service.recognize(path),
          throwsA(errorCode('OCR_INVALID_ARGUMENT')),
        );
      }
      await expectLater(
        service.recognize('/private/a.jpg', language: 'download-me'),
        throwsA(errorCode('OCR_INVALID_ARGUMENT')),
      );
      expect(calls, 0);
    },
  );

  test('concurrent recognition does not duplicate a native request', () async {
    final response = Completer<Object?>();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) {
      calls++;
      return response.future;
    });
    final first = service.recognize('/private/a.jpg');
    expect(service.isRecognizing, isTrue);
    await expectLater(
      service.recognize('/private/b.jpg'),
      throwsA(errorCode('OCR_BUSY')),
    );
    response.complete({'text': 'A', 'confidence': 1});
    expect((await first).text, 'A');
    expect(calls, 1);
  });

  test(
    'cancel targets the same request and suppresses a late successful response',
    () async {
      final response = Completer<Object?>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return call.method == 'recognize' ? response.future : Future.value();
      });
      final first = service.recognize('/private/a.jpg');
      final expectation = expectLater(
        first,
        throwsA(errorCode('OCR_CANCELLED')),
      );
      await service.cancel();
      await service.cancel();
      expect(calls.map((call) => call.method), ['recognize', 'cancel']);
      expect(
        calls.last.arguments['requestId'],
        calls.first.arguments['requestId'],
      );
      response.complete({'text': 'late sensitive result', 'confidence': 0.9});
      await expectation;
      expect(service.isRecognizing, isFalse);
    },
  );

  test('idle cancellation invokes no native method', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    await service.cancel();
    expect(calls, 0);
  });

  test(
    'native errors retain stable code, never expose native sensitive details',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'OCR_INVALID_PATH',
          message: '/sensitive/path bank text',
          details: 'secret',
        );
      });
      try {
        await service.recognize('/private/a.jpg');
        fail('Expected an OCR exception');
      } on ReceiptOcrException catch (error) {
        expect(error.code, 'OCR_INVALID_PATH');
        expect(error.message, isNot(contains('sensitive')));
        expect(error.toString(), isNot(contains('secret')));
      }
      expect(service.isRecognizing, isFalse);
    },
  );

  for (final code in [
    'OCR_IMAGE_TOO_LARGE',
    'OCR_INVALID_IMAGE',
    'OCR_MODELS_MISSING',
    'OCR_MODELS_INVALID',
    'OCR_BUSY',
    'OCR_OUTPUT_TOO_LARGE',
    'OCR_FAILED',
    'OCR_UNAVAILABLE',
    'OCR_CANCELLED',
  ]) {
    test(
      'surfaces native $code instead of pretending successful OCR',
      () async {
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: code);
        });
        await expectLater(
          service.recognize('/private/a.jpg'),
          throwsA(errorCode(code)),
        );
        expect(service.isRecognizing, isFalse);
      },
    );
  }

  test(
    'missing native implementation is explicit and never downloads a fallback',
    () async {
      await expectLater(
        service.recognize('/private/a.jpg'),
        throwsA(errorCode('OCR_UNAVAILABLE')),
      );
    },
  );

  test('malformed or unbounded native responses are rejected', () async {
    for (final response in [
      null,
      'plain text',
      {'text': 10, 'confidence': 0.5},
      {'text': 'a'},
      {'text': 'a', 'confidence': double.nan},
      {'text': 'a', 'confidence': double.infinity},
      {'text': 'a', 'confidence': -0.1},
      {'text': 'a', 'confidence': 1.1},
      {'text': 'a' * 100001, 'confidence': 0.8},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      await expectLater(
        service.recognize('/private/a.jpg'),
        throwsA(errorCode('OCR_INVALID_RESPONSE')),
      );
      expect(service.isRecognizing, isFalse);
    }
  });

  test(
    'service can be reused after an error with a fresh unique native ID',
    () async {
      final ids = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        ids.add(call.arguments['requestId'] as String);
        if (ids.length == 1) throw PlatformException(code: 'OCR_INVALID_IMAGE');
        return {'text': 'retry works', 'confidence': 0.8};
      });
      await expectLater(
        service.recognize('/private/a.jpg'),
        throwsA(errorCode('OCR_INVALID_IMAGE')),
      );
      expect((await service.recognize('/private/b.jpg')).text, 'retry works');
      expect(ids.toSet(), hasLength(2));
    },
  );

  test(
    'cancel failure is surfaced and a late response is still discarded',
    () async {
      final response = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancel') {
          throw PlatformException(code: 'OCR_FAILED');
        }
        return response.future;
      });
      final first = service.recognize('/private/a.jpg');
      final expectation = expectLater(
        first,
        throwsA(errorCode('OCR_CANCELLED')),
      );
      await expectLater(service.cancel(), throwsA(errorCode('OCR_FAILED')));
      response.complete({'text': 'late', 'confidence': 1});
      await expectation;
    },
  );
}
