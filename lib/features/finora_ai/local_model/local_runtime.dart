import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'assistant_diagnostics.dart';

typedef ModelMessage = Map<String, String>;

/// The only route to the bundled runtime. No network or ledger access.
class LocalRuntime {
  LocalRuntime({MethodChannel? channel, Stream<dynamic>? events})
    : _channel = channel ?? const MethodChannel('finora/local_llm'),
      _events = events;

  static final instance = LocalRuntime();
  final MethodChannel _channel;
  final Stream<dynamic>? _events;
  String? _loadedPath;
  String? _active;
  bool _cancelled = false;
  bool _loading = false;
  Timer? _idle;
  Map<String, Object?> lastMetrics = {};

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get busy => _active != null || _loading;
  bool get loaded => _loadedPath != null;

  Future<void> load(String path) async {
    if (!supported) {
      throw const FormatException(
        'Локальная модель доступна только на Android.',
      );
    }
    if (busy) throw const FormatException('Дождитесь остановки модели.');
    _loading = true;
    _idle?.cancel();
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('load', {
        'path': path,
        'contextTokens': 2048,
      });
      _loadedPath = path;
      lastMetrics = {...?result};
    } finally {
      _loading = false;
      _armIdle();
    }
  }

  /// Measures the actual chat template with MNN's tokenizer, including its
  /// assistant-generation suffix. The reserved answer is part of the budget.
  Future<List<ModelMessage>> fitContext({
    required String instructions,
    required String user,
    List<ModelMessage> history = const [],
    List<ModelMessage> context = const [],
  }) async {
    final turns = history.map((m) => Map<String, String>.of(m)).toList();
    final optional = context.map((m) => Map<String, String>.of(m)).toList();
    while (true) {
      final messages = <ModelMessage>[
        {'role': 'system', 'content': instructions},
        ...optional,
        ...turns,
        {'role': 'user', 'content': user},
      ];
      final measured = await _channel.invokeMapMethod<String, Object?>(
        'tokenize',
        {'messages': messages},
      );
      final tokens = measured?['tokens'];
      if (tokens is! int || tokens < 1) {
        throw const FormatException('Токенизатор модели недоступен.');
      }
      if (tokens + 256 <= 2048) return messages;
      if (turns.isNotEmpty) {
        turns.removeAt(0);
        // Keep complete user/assistant turns rather than a dangling reply.
        while (turns.isNotEmpty && turns.first['role'] != 'user') {
          turns.removeAt(0);
        }
      } else if (optional.isNotEmpty) {
        optional.removeLast();
      } else {
        throw const FormatException(
          'Сообщение слишком длинное для контекста модели. Сократите его.',
        );
      }
    }
  }

  Future<String> generate({
    required String id,
    required List<ModelMessage> messages,
    required void Function(String text) onDelta,
  }) async {
    if (busy || !loaded) throw const FormatException('Модель ещё не готова.');
    _active = id;
    _cancelled = false;
    _idle?.cancel();
    final output = StringBuffer();
    final events =
        _events ??
        const EventChannel('finora/local_llm/events').receiveBroadcastStream();
    Object? eventError;
    final subscription = events.listen(
      (event) {
        if (event is! Map || event['id'] != id || _cancelled) return;
        if (event['type'] == 'delta' && event['text'] is String) {
          final delta = event['text'] as String;
          if (output.length + delta.length > 32768) {
            eventError = const FormatException(
              'Ответ модели превышает допустимый размер.',
            );
            _cancelInBackground();
            return;
          }
          output.write(delta);
          onDelta(output.toString());
        }
      },
      onError: (Object e) {
        eventError = e;
        _cancelInBackground();
      },
    );
    try {
      // Native code also enforces the timeout and observes the atomic stop
      // flag. Dart never considers a timed-out/partial answer executable.
      final result = await _channel
          .invokeMapMethod<String, Object?>('generate', {
            'id': id,
            'messages': messages,
            'maxTokens': 256,
            'contextTokens': 2048,
          })
          .timeout(
            const Duration(minutes: 3),
            onTimeout: () async {
              await cancel();
              throw const FormatException('Модель не ответила вовремя.');
            },
          );
      lastMetrics = result?['metrics'] is Map
          ? Map<String, Object?>.from(result!['metrics'] as Map)
          : {...?result};
      if (eventError != null) throw eventError!;
      if (_cancelled || result?['reason'] == 'cancelled') {
        throw const ModelCancelled();
      }
      if (result?['reason'] != 'completed') {
        throw const FormatException(
          'Ответ модели не завершён. Попробуйте более короткий запрос.',
        );
      }
      // The completed future is the native worker's fence. It may include
      // text for reliable delivery even if the event queue lagged behind.
      return result?['text'] is String
          ? result!['text'] as String
          : output.toString();
    } finally {
      await subscription.cancel();
      _active = null;
      _armIdle();
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    final id = _active;
    if (id != null) await _channel.invokeMethod<void>('cancel', {'id': id});
  }

  Future<void> unload() async {
    _idle?.cancel();
    await cancel();
    // Native unload queues behind the generation; no native object is freed
    // while generate/tokenize/load still owns it.
    if (supported) {
      try {
        await _channel.invokeMethod<void>('unload');
      } on MissingPluginException {
        if (busy) rethrow;
      } on PlatformException catch (e) {
        if (e.code != 'unsupported' || busy) rethrow;
      }
    }
    _loadedPath = null;
  }

  Future<Map<String, Object?>> diagnostics() async => supported
      ? {...?await _channel.invokeMapMethod<String, Object?>('diagnostics')}
      : {'available': false, 'platform': defaultTargetPlatform.name};

  void _cancelInBackground() => unawaited(
    cancel().catchError((Object _) {
      AssistantDiagnostics.instance.record('cancel_error');
    }),
  );

  void _armIdle() {
    _idle?.cancel();
    if (!supported) return;
    _idle = Timer(
      const Duration(minutes: 2),
      () => unawaited(
        unload().catchError((Object _) {
          AssistantDiagnostics.instance.record('idle_release_error');
        }),
      ),
    );
  }
}

class ModelCancelled implements Exception {
  const ModelCancelled();
}
