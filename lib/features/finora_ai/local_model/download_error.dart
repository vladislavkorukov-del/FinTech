import 'dart:io';

import '../../../services/user_error.dart';

enum ModelDownloadErrorCode {
  dns,
  networkUnavailable,
  tls,
  connectTimeout,
  idleTimeout,
  connectionClosed,
  unauthorized,
  forbidden,
  notFound,
  rateLimited,
  serverUnavailable,
  http,
  noSpace,
  write,
  checksum,
  invalidPayload,
  invalidRange,
  invalidResponse,
  busy,
  unknown,
}

class ModelDeliveryException implements Exception, UserFacingFailure {
  const ModelDeliveryException(this.message);
  final String message;
  @override
  String get userMessage => message;
  @override
  String toString() => message;
}

/// Safe to present to a person. Original socket exceptions and signed URLs
/// are never retained by this error or its diagnostics.
class ModelDownloadFailure extends ModelDeliveryException {
  const ModelDownloadFailure(
    this.code,
    super.message, {
    this.retryable = false,
    this.stage = 'download',
    this.status,
    this.host,
    this.attempt = 1,
    this.savedBytes = 0,
    this.retryAt,
  });
  final ModelDownloadErrorCode code;
  final bool retryable;
  final String stage;
  final int? status;
  final String? host;
  final int attempt, savedBytes;
  final DateTime? retryAt;

  ModelDownloadFailure withContext({
    String? stage,
    String? host,
    int? attempt,
    int? savedBytes,
  }) => ModelDownloadFailure(
    code,
    message,
    retryable: retryable,
    stage: stage ?? this.stage,
    status: status,
    host: host ?? this.host,
    attempt: attempt ?? this.attempt,
    savedBytes: savedBytes ?? this.savedBytes,
    retryAt: retryAt,
  );

  Map<String, Object?> diagnostics() => {
    'code': code.name,
    'stage': stage,
    'retryable': retryable,
    if (status != null) 'httpStatus': status,
    if (host != null) 'host': host,
    'attempt': attempt,
    'savedBytes': savedBytes,
    if (retryAt != null) 'retryAt': retryAt!.toIso8601String(),
  };
}

String sanitizeDownloadDetails(Object value) => value
    .toString()
    .replaceAllMapped(RegExp(r'https?://[^\s<>"\)]+', caseSensitive: false), (
      m,
    ) {
      final uri = Uri.tryParse(m[0]!);
      return uri == null
          ? '[URL скрыт]'
          : '${uri.scheme}://${uri.host}/[параметры скрыты]';
    })
    .replaceAll(
      RegExp(r'authorization\s*[:=]\s*[^\r\n]+', caseSensitive: false),
      '[авторизация скрыта]',
    )
    .replaceAll(
      RegExp(r'\bbearer\s+[^\s,;]+', caseSensitive: false),
      '[токен скрыт]',
    )
    .replaceAll(
      RegExp(
        r'(authorization|bearer|token|signature|x-amz-[a-z-]+)\s*[:= ]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      '[секрет скрыт]',
    );

ModelDownloadFailure classifyDownloadError(
  Object error, {
  String stage = 'download',
}) {
  if (error is ModelDownloadFailure) return error;
  if (error is HandshakeException || error is TlsException) {
    return const ModelDownloadFailure(
      ModelDownloadErrorCode.tls,
      'Не удалось установить защищённое соединение с источником модели.',
      stage: 'tls',
    );
  }
  if (error is FileSystemException) {
    final full =
        error.osError?.errorCode == 28 || error.osError?.errorCode == 112;
    return ModelDownloadFailure(
      full ? ModelDownloadErrorCode.noSpace : ModelDownloadErrorCode.write,
      full
          ? 'Недостаточно свободного места.'
          : 'Не удалось записать файл модели. Проверьте свободное место.',
      stage: 'write',
    );
  }
  if (error is SocketException) {
    final text = error.message.toLowerCase();
    final dns =
        text.contains('host lookup') ||
        text.contains('name resolution') ||
        text.contains('nodename');
    final unavailable = [
      51,
      64,
      65,
      101,
      113,
    ].contains(error.osError?.errorCode);
    return ModelDownloadFailure(
      dns
          ? ModelDownloadErrorCode.dns
          : unavailable
          ? ModelDownloadErrorCode.networkUnavailable
          : ModelDownloadErrorCode.connectionClosed,
      dns
          ? 'Не удалось найти источник модели. Можно повторить загрузку.'
          : unavailable
          ? 'Сеть сейчас недоступна. Загрузку можно продолжить позже.'
          : 'Загрузка прервалась. Можно продолжить.',
      retryable: true,
      stage: stage,
    );
  }
  if (error is HttpException) {
    return ModelDownloadFailure(
      ModelDownloadErrorCode.connectionClosed,
      'Загрузка прервалась. Можно продолжить.',
      retryable: true,
      stage: stage,
    );
  }
  return ModelDownloadFailure(
    ModelDownloadErrorCode.unknown,
    'Загрузка не завершена. Можно повторить.',
    stage: stage,
  );
}
