import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Errors explicitly safe to show. Technical exceptions must never become
/// snackbars by interpolation (network errors may contain signed URLs).
abstract interface class UserFacingFailure {
  String get userMessage;
}

String redactDiagnosticText(String value) => value
    .replaceAll(
      RegExp(r'authorization\s*[:=][^\r\n]*', caseSensitive: false),
      '[авторизация скрыта]',
    )
    .replaceAll(
      RegExp(r'bearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false),
      '[токен скрыт]',
    )
    .replaceAll(
      RegExp(r'https?://[^\s<>"\x27]+', caseSensitive: false),
      '[ссылка скрыта]',
    )
    .replaceAll(
      RegExp(
        r'(authorization|token|signature|credential|password|secret)\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      '[секрет скрыт]',
    );

String userErrorMessage(Object error) {
  final String text;
  if (error is UserFacingFailure) {
    text = error.userMessage;
  } else if (error is FormatException) {
    text = error.message;
  } else if (error is String) {
    text = error;
  } else if (error is HandshakeException || error is TlsException) {
    text = 'Не удалось установить защищённое соединение. Попробуйте позже.';
  } else if (error is SocketException || error is HttpException) {
    text = 'Соединение прервалось. Можно повторить действие.';
  } else if (error is TimeoutException) {
    text = 'Ответ не получен вовремя. Попробуйте ещё раз.';
  } else if (error is FileSystemException) {
    text = error.osError?.errorCode == 28
        ? 'Недостаточно свободного места.'
        : 'Не удалось записать файл. Проверьте свободное место.';
  } else if (error is PlatformException) {
    text = 'Действие недоступно или не завершилось. Попробуйте ещё раз.';
  } else {
    text = 'Не удалось выполнить действие. Попробуйте ещё раз.';
  }
  final safe = redactDiagnosticText(
    text,
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
  return safe.runes.length <= 240
      ? safe
      : '${String.fromCharCodes(safe.runes.take(237))}…';
}
