import 'package:flutter/services.dart';

/// Text only: OCR never creates, saves or uploads financial operations.
class ReceiptOcrResult {
  final String text;

  /// Mean word confidence from Tesseract, normalized to 0..1 (not a guarantee).
  final double confidence;

  const ReceiptOcrResult({required this.text, required this.confidence});
}

class ReceiptOcrException implements Exception {
  final String code;
  final String message;

  const ReceiptOcrException(this.code, this.message);

  bool get cancelled => code == 'OCR_CANCELLED';

  @override
  String toString() => message;
}

/// Android's bundled Russian/English OCR. Input must already be copied into
/// app-private storage. The native bridge validates the canonical file path.
class ReceiptOcrService {
  final MethodChannel _channel;
  static int _sequence = 0;
  _OcrRequest? _active;

  ReceiptOcrService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('finora/ocr');

  bool get isRecognizing => _active != null;

  Future<ReceiptOcrResult> recognize(
    String path, {
    String language = 'rus+eng',
  }) async {
    if (_active != null) {
      throw const ReceiptOcrException(
        'OCR_BUSY',
        'Распознавание уже выполняется.',
      );
    }
    if (language != 'rus+eng' ||
        !path.startsWith('/') ||
        path.contains('://') ||
        path.contains('\u0000')) {
      throw const ReceiptOcrException(
        'OCR_INVALID_ARGUMENT',
        'Выберите локальное изображение для распознавания.',
      );
    }
    final request = _OcrRequest('receipt-${++_sequence}');
    _active = request;
    try {
      final response = await _channel.invokeMethod<Object?>('recognize', {
        'path': path,
        'language': language,
        'requestId': request.id,
      });
      if (request.cancelled) throw _cancelled;
      if (response is! Map ||
          response['text'] is! String ||
          response['confidence'] is! num) {
        throw _invalidResponse;
      }
      final confidence = (response['confidence'] as num).toDouble();
      final text = response['text'] as String;
      if (!confidence.isFinite ||
          confidence < 0 ||
          confidence > 1 ||
          text.length > 100000) {
        throw _invalidResponse;
      }
      return ReceiptOcrResult(text: text, confidence: confidence);
    } on PlatformException catch (error) {
      if (request.cancelled) throw _cancelled;
      throw ReceiptOcrException(error.code, _message(error.code));
    } on MissingPluginException {
      throw const ReceiptOcrException(
        'OCR_UNAVAILABLE',
        'Офлайн-распознавание доступно в Android-приложении.',
      );
    } finally {
      if (identical(_active, request)) _active = null;
    }
  }

  /// Cancels result delivery immediately on Android. An already running native
  /// UTF8 pass finishes on its worker before native memory can safely be freed.
  Future<void> cancel() async {
    final request = _active;
    if (request == null || request.cancelled) return;
    request.cancelled = true;
    try {
      await _channel.invokeMethod<void>('cancel', {'requestId': request.id});
    } on PlatformException catch (error) {
      throw ReceiptOcrException(error.code, _message(error.code));
    } on MissingPluginException {
      throw const ReceiptOcrException(
        'OCR_UNAVAILABLE',
        'Офлайн-распознавание доступно в Android-приложении.',
      );
    }
  }

  static const _cancelled = ReceiptOcrException(
    'OCR_CANCELLED',
    'Распознавание отменено.',
  );
  static const _invalidResponse = ReceiptOcrException(
    'OCR_INVALID_RESPONSE',
    'Не удалось прочитать результат распознавания.',
  );

  static String _message(String code) => switch (code) {
    'OCR_CANCELLED' => 'Распознавание отменено.',
    'OCR_BUSY' =>
      'Распознавание уже выполняется. Попробуйте через несколько секунд.',
    'OCR_INVALID_PATH' || 'OCR_INVALID_ARGUMENT' =>
      'Выберите локальное изображение для распознавания.',
    'OCR_IMAGE_TOO_LARGE' => 'Изображение слишком большое. Максимум — 20 МБ.',
    'OCR_INVALID_IMAGE' =>
      'Не удалось прочитать изображение. Выберите другой файл.',
    'OCR_MODELS_MISSING' || 'OCR_MODELS_INVALID' || 'OCR_UNAVAILABLE' =>
      'Офлайн-модуль распознавания недоступен. Переустановите приложение.',
    'OCR_OUTPUT_TOO_LARGE' =>
      'На изображении слишком много текста. Выберите нужный фрагмент.',
    _ => 'Не удалось распознать текст. Попробуйте более чёткое изображение.',
  };
}

class _OcrRequest {
  final String id;
  bool cancelled = false;

  _OcrRequest(this.id);
}
