import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Device-local access gate. Financial data remains in the application's sandbox;
/// this gate is deliberately independent of export/backup files.
class SecurityService {
  static final revision = ValueNotifier<int>(0);
  SecurityService({FlutterSecureStorage? storage, LocalAuthentication? auth})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          ),
      _auth = auth ?? LocalAuthentication();

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;
  static const _pinKey = 'finora.pin.v1';
  static const _attemptKey = 'finora.pin.attempts';
  static const _biometricKey = 'finora.biometric';
  static const _iterations = 210000;
  bool _verifying = false;

  Future<bool> hasPin() async => await _storage.read(key: _pinKey) != null;

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw const FormatException('PIN должен содержать от 4 до 6 цифр');
    }
    final random = Random.secure();
    final salt = List<int>.generate(32, (_) => random.nextInt(256));
    final hash = await Isolate.run(() => _derivePin(pin, salt, _iterations));
    await _storage.write(
      key: _pinKey,
      value: jsonEncode({
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
        'iterations': _iterations,
      }),
    );
    await _storage.delete(key: _attemptKey);
    revision.value++;
  }

  /// Fails closed when secure storage is unavailable. Failed attempts and their
  /// increasing delay survive application restarts.
  Future<bool> verifyPin(String pin) async {
    if (_verifying) {
      return false;
    }
    _verifying = true;
    try {
      final record = await _storage.read(key: _pinKey);
      if (record == null) {
        return false;
      }
      final attempt = await _storage.read(key: _attemptKey);
      final state = attempt == null
          ? <String, dynamic>{}
          : jsonDecode(attempt) as Map<String, dynamic>;
      final blockedUntil = (state['until'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch < blockedUntil) {
        throw const FormatException(
          'Слишком много попыток. Подождите перед повторным вводом.',
        );
      }
      final saved = jsonDecode(record) as Map<String, dynamic>;
      final salt = base64Decode(saved['salt'] as String);
      final expected = base64Decode(saved['hash'] as String);
      final iterations = (saved['iterations'] as num).toInt();
      if (iterations < 100000 || iterations > 1000000) {
        throw const FormatException('Повреждена настройка безопасности');
      }
      final actual = await Isolate.run(() => _derivePin(pin, salt, iterations));
      var difference = actual.length ^ expected.length;
      for (var i = 0; i < actual.length && i < expected.length; i++) {
        difference |= actual[i] ^ expected[i];
      }
      if (difference == 0) {
        await _storage.delete(key: _attemptKey);
        return true;
      }
      final failures = ((state['failures'] as num?)?.toInt() ?? 0) + 1;
      final seconds = failures < 5
          ? 0
          : min(3600, 30 * pow(2, min(7, failures - 5))).toInt();
      await _storage.write(
        key: _attemptKey,
        value: jsonEncode({
          'failures': failures,
          'until': DateTime.now()
              .add(Duration(seconds: seconds))
              .millisecondsSinceEpoch,
        }),
      );
      return false;
    } finally {
      _verifying = false;
    }
  }

  Future<void> removePin() async {
    await _storage.delete(key: _biometricKey);
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _attemptKey);
    revision.value++;
  }

  Future<bool> get biometricEnabled async =>
      await hasPin() && await _storage.read(key: _biometricKey) == 'true';

  Future<bool> get biometricAvailable async {
    try {
      return await _auth.isDeviceSupported() &&
          await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (enabled && (!await hasPin() || !await biometricAvailable)) {
      throw const FormatException(
        'Сначала установите PIN и добавьте биометрию в настройках Android',
      );
    }
    await _storage.write(key: _biometricKey, value: enabled.toString());
    revision.value++;
  }

  Future<bool> authenticateBiometric() async {
    if (!await biometricEnabled || !await biometricAvailable) {
      return false;
    }
    try {
      return await _auth.authenticate(
        localizedReason: 'Подтвердите вход в Finora',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}

/// PBKDF2-HMAC-SHA256, one 32-byte block, with a random per-installation salt.
/// Runs in an isolate so key derivation does not block amount entry or animations.
List<int> _derivePin(String pin, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, utf8.encode(pin));
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final output = List<int>.from(u);
  for (var round = 1; round < iterations; round++) {
    u = hmac.convert(u).bytes;
    for (var i = 0; i < output.length; i++) {
      output[i] ^= u[i];
    }
  }
  return output;
}
