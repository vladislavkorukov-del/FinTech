import 'dart:async';

import 'package:flutter/services.dart';

class ReceiptShareException implements Exception {
  final String code;
  final String message;

  const ReceiptShareException(this.code, this.message);

  @override
  String toString() => message;
}

/// Optional Android share target. Call [takePendingImage] after subscribing and
/// after each event: cold-start intents may arrive before Dart is listening.
class ReceiptShareService {
  final MethodChannel _channel;
  final _events = StreamController<void>.broadcast();
  bool _disposed = false;

  ReceiptShareService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('finora/receipt_share') {
    _channel.setMethodCallHandler((call) async {
      if (_disposed) return;
      if (call.method == 'imageAvailable' || call.method == 'shareError') {
        // takePendingImage consumes either the pending path or pending error,
        // preventing duplicate error delivery to an event + cold-start check.
        _events.add(null);
      }
    });
  }

  /// Signals a pending image or input error; takePendingImage consumes it once.
  Stream<void> get imageAvailable => _events.stream;

  Future<String?> takePendingImage() async {
    if (_disposed) return null;
    try {
      final value = await _channel.invokeMethod<Object?>('takeSharedImage');
      if (value == null) return null;
      if (value is! String ||
          !value.startsWith('/') ||
          value.contains('://') ||
          value.contains('\u0000')) {
        throw const ReceiptShareException(
          'SHARE_INVALID_RESPONSE',
          'Не удалось получить изображение.',
        );
      }
      return value;
    } on MissingPluginException {
      // Sharing is optional on desktop, web and widget-test hosts.
      return null;
    } on PlatformException catch (error) {
      throw ReceiptShareException(error.code, switch (error.code) {
        'SHARE_IMAGE_TOO_LARGE' =>
          'Изображение слишком большое. Максимум — 20 МБ.',
        'SHARE_INVALID_IMAGE' => 'Поделиться можно только скриншотом из банка.',
        'SHARE_BUSY' => 'Дождитесь загрузки предыдущего изображения.',
        _ =>
          'Не удалось открыть изображение. Попробуйте выбрать его из галереи.',
      });
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    await _events.close();
  }
}
