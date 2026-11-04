import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finora/services/security_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  // Independently generated with Python hashlib.pbkdf2_hmac, SHA256,
  // password "123456", salt bytes 0..31, 210000 rounds, 32-byte output.
  const salt = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
  const hash = 'mwmeZZ61hOwqSonf1655hIrWDd8GX9gAe5ymkoXtEw8=';
  final referenceRecord = jsonEncode({
    'salt': salt,
    'hash': hash,
    'iterations': 210000,
  });

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('an unconfigured device has no PIN and cannot verify a PIN', () async {
    final service = SecurityService();
    expect(await service.hasPin(), isFalse);
    expect(await service.verifyPin('123456'), isFalse);
    expect(await service.biometricEnabled, isFalse);
  });

  test('only four to six ASCII digits can be configured as a PIN', () async {
    final service = SecurityService();
    for (final invalid in ['', '123', '1234567', '12a4', '１２３４', '12 34']) {
      await expectLater(service.setPin(invalid), throwsFormatException);
    }
    expect(await service.hasPin(), isFalse);
  });

  test(
    'PBKDF2 verification agrees with an independent known-answer vector',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'finora.pin.v1': referenceRecord,
      });
      expect(await SecurityService().verifyPin('123456'), isTrue);
      expect(await SecurityService().verifyPin('123455'), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'PIN persists across service instances and receives a fresh salt',
    () async {
      final service = SecurityService();
      await service.setPin('9876');
      final first =
          jsonDecode((await storage.read(key: 'finora.pin.v1'))!)
              as Map<String, dynamic>;
      expect(first['hash'], isNot('9876'));
      expect(base64Decode(first['salt'] as String), hasLength(32));
      expect(base64Decode(first['hash'] as String), hasLength(32));
      expect(await SecurityService().verifyPin('9876'), isTrue);
      await service.setPin('9876');
      final second =
          jsonDecode((await storage.read(key: 'finora.pin.v1'))!)
              as Map<String, dynamic>;
      expect(second['salt'], isNot(first['salt']));
      expect(second['hash'], isNot(first['hash']));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'fifth wrong PIN enables a cooldown that survives service recreation',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'finora.pin.v1': referenceRecord,
        'finora.pin.attempts': jsonEncode({'failures': 4, 'until': 0}),
      });
      expect(await SecurityService().verifyPin('111111'), isFalse);
      final attempts =
          jsonDecode((await storage.read(key: 'finora.pin.attempts'))!)
              as Map<String, dynamic>;
      expect(attempts['failures'], 5);
      expect(
        attempts['until'] as int,
        greaterThan(DateTime.now().millisecondsSinceEpoch),
      );
      await expectLater(
        SecurityService().verifyPin('123456'),
        throwsFormatException,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('successful PIN clears expired lockout history', () async {
    FlutterSecureStorage.setMockInitialValues({
      'finora.pin.v1': referenceRecord,
      'finora.pin.attempts': jsonEncode({'failures': 5, 'until': 0}),
    });
    expect(await SecurityService().verifyPin('123456'), isTrue);
    expect(await storage.read(key: 'finora.pin.attempts'), isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('corrupt credentials fail closed instead of accepting a PIN', () async {
    FlutterSecureStorage.setMockInitialValues({
      'finora.pin.v1': 'invalid-json',
    });
    await expectLater(
      SecurityService().verifyPin('123456'),
      throwsFormatException,
    );
  });

  test('biometrics cannot be enabled without a PIN', () async {
    await expectLater(
      SecurityService().setBiometricEnabled(true),
      throwsFormatException,
    );
    expect(await SecurityService().biometricEnabled, isFalse);
  });

  test('removing PIN removes biometric access and retry history', () async {
    FlutterSecureStorage.setMockInitialValues({
      'finora.pin.v1': referenceRecord,
      'finora.biometric': 'true',
      'finora.pin.attempts': jsonEncode({'failures': 2, 'until': 0}),
    });
    final service = SecurityService();
    expect(await service.biometricEnabled, isTrue);
    await service.removePin();
    expect(await service.hasPin(), isFalse);
    expect(await service.biometricEnabled, isFalse);
    expect(await storage.read(key: 'finora.pin.attempts'), isNull);
  });
}
