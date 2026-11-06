import 'package:flutter/services.dart';
import '../domain/scan_document.dart';

/// Text only: OCR never creates, saves or uploads financial operations.
class ReceiptOcrResult {
  final String text;

  /// Mean word confidence from Tesseract, normalized to 0..1 (not a guarantee).
  final double confidence;
  final List<RecognizedLine> lines;

  /// Digits-only re-reads of the amount column of a bank list, one per row
  /// (optional; empty for older native builds and for receipts).
  final List<RecognizedLine> amountLines;

  const ReceiptOcrResult({
    required this.text,
    required this.confidence,
    this.lines = const [],
    this.amountLines = const [],
  });
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
      final lines = _decodeLines(response['lines'], maxLines: 3000);
      final amountLines = _decodeLines(
        response['amounts'],
        maxLines: 200,
        maxText: 512,
      );
      return ReceiptOcrResult(
        text: text,
        confidence: confidence,
        lines: lines,
        amountLines: amountLines,
      );
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

  /// Validates native line geometry: text plus left/top/right/bottom and
  /// confidence, all finite numbers in 0..1, bounded counts and sizes.
  List<RecognizedLine> _decodeLines(
    Object? raw, {
    required int maxLines,
    int maxText = 8192,
  }) {
    if (raw == null) return const [];
    if (raw is! List || raw.length > maxLines) throw _invalidResponse;
    final lines = <RecognizedLine>[];
    var totalCharacters = 0;
    for (final item in raw) {
      if (item is! Map || item['text'] is! String) throw _invalidResponse;
      final values = <double>[];
      for (final field in ['left', 'top', 'right', 'bottom', 'confidence']) {
        final value = item[field];
        if (value is! num || !value.isFinite || value < 0 || value > 1) {
          throw _invalidResponse;
        }
        values.add(value.toDouble());
      }
      final lineText = item['text'] as String;
      totalCharacters += lineText.length;
      if (lineText.length > maxText ||
          totalCharacters > 100000 ||
          values[0] > values[2] ||
          values[1] > values[3]) {
        throw _invalidResponse;
      }
      lines.add(
        RecognizedLine(
          text: lineText,
          left: values[0],
          top: values[1],
          right: values[2],
          bottom: values[3],
          confidence: values[4],
        ),
      );
    }
    return List.unmodifiable(lines);
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
