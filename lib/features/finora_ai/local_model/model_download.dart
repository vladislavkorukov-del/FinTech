import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'download_error.dart';
import 'model_manifest.dart';
export 'download_error.dart';

enum ModelDownloadPhase {
  downloading,
  retrying,
  paused,
  verifying,
  ready,
  cancelled,
  failed,
}

class ModelDownloadProgress {
  const ModelDownloadProgress(
    this.receivedBytes,
    this.totalBytes,
    this.phase, {
    this.attempt = 1,
    this.maxAttempts = 3,
    this.retryAt,
  });
  final int receivedBytes, totalBytes, attempt, maxAttempts;
  final ModelDownloadPhase phase;
  final DateTime? retryAt;
  double get fraction => totalBytes == 0
      ? 0
      : (receivedBytes / totalBytes).clamp(
          0,
          phase == ModelDownloadPhase.ready ? 1 : .999,
        );
}

class ModelDownloadCancelled implements Exception {
  const ModelDownloadCancelled();
  @override
  String toString() => 'Скачивание приостановлено';
}

abstract interface class ModelTransport {
  Future<ModelResponse> get(Uri url, {required int offset});
  void close();
}

/// Additive capability: old test/adapters need not implement validators.
abstract interface class ModelValidatorTransport implements ModelTransport {
  void setValidator(String? validator);
}

class ModelResponse {
  const ModelResponse({
    required this.status,
    required this.body,
    this.contentLength = -1,
    this.contentRange,
    this.contentType,
    this.etag,
    this.lastModified,
    this.retryAfter,
    this.host,
    this.contentEncoding,
  });
  final int status, contentLength;
  final String? contentRange,
      contentType,
      etag,
      lastModified,
      retryAfter,
      host,
      contentEncoding;
  final Stream<List<int>> body;
}

/// Production requests always start at the pinned HTTPS resolve URL. The only
/// HTTP exception is an explicit test constructor restricted to loopback.
class HttpsModelTransport implements ModelValidatorTransport {
  HttpsModelTransport({
    this.connectTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 45),
  }) : _loopback = null {
    _configure();
  }
  HttpsModelTransport.forTesting({
    required Uri loopbackOrigin,
    this.connectTimeout = const Duration(seconds: 2),
    this.idleTimeout = const Duration(seconds: 2),
  }) : _loopback = loopbackOrigin {
    if (loopbackOrigin.scheme != 'http' ||
        !['127.0.0.1', 'localhost', '::1'].contains(loopbackOrigin.host)) {
      throw ArgumentError(
        'Only explicit loopback HTTP is allowed for transport tests',
      );
    }
    _configure();
  }
  final Duration connectTimeout, idleTimeout;
  final Uri? _loopback;
  final _client = HttpClient();
  String? _validator;
  bool _closed = false;
  void _configure() {
    _client.connectionTimeout = connectTimeout;
    _client.autoUncompress = false;
  }

  @override
  void setValidator(String? validator) => _validator = validator;
  bool _permitted(Uri uri) =>
      uri.scheme == 'https' ||
      (_loopback != null &&
          uri.scheme == 'http' &&
          uri.host == _loopback.host &&
          uri.port == _loopback.port);
  @override
  Future<ModelResponse> get(Uri url, {required int offset}) async {
    if (url.scheme != 'https') {
      throw const ModelDownloadFailure(
        ModelDownloadErrorCode.invalidResponse,
        'Для модели требуется HTTPS.',
      );
    }
    var current = _loopback == null
        ? url
        : _loopback.replace(path: url.path, query: url.query);
    try {
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (!_permitted(current) || current.userInfo.isNotEmpty) {
          throw const ModelDownloadFailure(
            ModelDownloadErrorCode.invalidResponse,
            'Небезопасное перенаправление загрузки.',
          );
        }
        if (_closed) throw const ModelDownloadCancelled();
        final request = await _client.getUrl(current).timeout(connectTimeout);
        request.followRedirects = false;
        // No Authorization/cookies supplied, including across host redirects.
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        if (offset > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
          if (_validator != null) {
            request.headers.set(HttpHeaders.ifRangeHeader, _validator!);
          }
        }
        final response = await request.close().timeout(connectTimeout);
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || redirects == 5) {
            throw const ModelDownloadFailure(
              ModelDownloadErrorCode.invalidResponse,
              'Источник модели вернул некорректное перенаправление.',
            );
          }
          final redirected = current.resolve(location);
          if (!_permitted(redirected)) {
            throw const ModelDownloadFailure(
              ModelDownloadErrorCode.invalidResponse,
              'Небезопасное перенаправление загрузки.',
            );
          }
          await response.drain<void>().timeout(idleTimeout);
          current = redirected;
          continue;
        }
        return ModelResponse(
          status: response.statusCode,
          body: response.timeout(
            idleTimeout,
            onTimeout: (sink) {
              sink.addError(
                ModelDownloadFailure(
                  ModelDownloadErrorCode.idleTimeout,
                  'Источник модели перестал передавать данные. Можно продолжить.',
                  retryable: true,
                  stage: 'body',
                  host: current.host,
                ),
              );
              sink.close();
            },
          ),
          contentLength: response.contentLength,
          contentRange: response.headers.value(HttpHeaders.contentRangeHeader),
          contentType: response.headers.contentType?.mimeType,
          contentEncoding: response.headers.value(
            HttpHeaders.contentEncodingHeader,
          ),
          etag: response.headers.value(HttpHeaders.etagHeader),
          lastModified: response.headers.value(HttpHeaders.lastModifiedHeader),
          retryAfter: response.headers.value(HttpHeaders.retryAfterHeader),
          host: current.host,
        );
      }
    } on TimeoutException {
      throw ModelDownloadFailure(
        ModelDownloadErrorCode.connectTimeout,
        'Не удалось дождаться соединения с источником модели. Можно повторить.',
        retryable: true,
        stage: 'connect',
        host: current.host,
      );
    } on ModelDownloadFailure {
      rethrow;
    } on ModelDownloadCancelled {
      rethrow;
    } catch (error) {
      throw classifyDownloadError(
        error,
        stage: 'connect',
      ).withContext(host: current.host);
    }
    throw const ModelDownloadFailure(
      ModelDownloadErrorCode.invalidResponse,
      'Слишком много перенаправлений.',
    );
  }

  @override
  void close() {
    _closed = true;
    _client.close(force: true);
  }
}

class ModelDownloadRetryPolicy {
  const ModelDownloadRetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 15),
    this.maxServerWait = const Duration(minutes: 2),
    this.jitterFraction = .2,
  });
  static const none = ModelDownloadRetryPolicy(maxAttempts: 1);
  final int maxAttempts;
  final Duration baseDelay, maxDelay, maxServerWait;
  final double jitterFraction;
  Duration delay(int failedAttempt, double random) {
    final raw = baseDelay.inMilliseconds * pow(2, failedAttempt - 1);
    return Duration(
      milliseconds:
          (min(raw, maxDelay.inMilliseconds) *
                  (1 + jitterFraction * (random * 2 - 1)))
              .round()
              .clamp(0, maxDelay.inMilliseconds),
    );
  }
}

class ModelDownloader {
  ModelDownloader({
    required this.stagingRoot,
    required this.freeBytes,
    this.onProgress,
    ModelTransport Function()? transport,
    this.onDiagnostic,
    this.retryPolicy = const ModelDownloadRetryPolicy(),
    double Function()? random,
    Future<void> Function(RandomAccessFile, List<int>)? writeChunk,
  }) : _transportFactory = transport ?? HttpsModelTransport.new,
       _random = random ?? Random().nextDouble,
       _writeChunk = writeChunk ?? _write;
  final Directory stagingRoot;
  final Future<int> Function(String path) freeBytes;
  final void Function(ModelDownloadProgress)? onProgress;
  final void Function(Map<String, Object?>)? onDiagnostic;
  final ModelDownloadRetryPolicy retryPolicy;
  final ModelTransport Function() _transportFactory;
  final double Function() _random;
  final Future<void> Function(RandomAccessFile, List<int>) _writeChunk;
  static Future<void> _write(RandomAccessFile file, List<int> chunk) async {
    await file.writeFrom(chunk);
  }

  static const diskReserveBytes = 64 * 1024 * 1024;
  static final _activePackages = <String>{};
  final _cancelSignal = Completer<void>();
  ModelTransport? _transport;
  bool _cancelled = false, _running = false;
  int _received = 0, _total = 0, _attempt = 1;
  ModelDownloadFailure? _reportedFailure;
  DateTime? _retryAt;
  void cancel() {
    _cancelled = true;
    if (!_cancelSignal.isCompleted) _cancelSignal.complete();
    _transport?.close();
  }

  void _checkCancelled() {
    if (_cancelled) throw const ModelDownloadCancelled();
  }

  Future<T> _cancellable<T>(Future<T> future) => Future.any([
    future,
    _cancelSignal.future.then<T>((_) => throw const ModelDownloadCancelled()),
  ]);
  void _emit(ModelDownloadPhase phase) => onProgress?.call(
    ModelDownloadProgress(
      _received,
      _total,
      phase,
      attempt: _attempt,
      maxAttempts: retryPolicy.maxAttempts,
      retryAt: _retryAt,
    ),
  );
  Future<void> _wait(Duration delay) async {
    final done = Completer<void>();
    final timer = Timer(delay, done.complete);
    try {
      await _cancellable(done.future);
    } finally {
      timer.cancel();
    }
  }

  Future<Directory> download(ModelManifest manifest) async {
    final stage = Directory(
      p.join(stagingRoot.absolute.path, manifest.packageKey),
    );
    final lockKey = p.normalize(stagingRoot.absolute.path);
    if (_running || !_activePackages.add(lockKey)) {
      throw const ModelDownloadFailure(
        ModelDownloadErrorCode.busy,
        'Эта модель уже скачивается.',
      );
    }
    _running = true;
    _total = manifest.downloadBytes;
    _received = 0;
    try {
      await stagingRoot.create(recursive: true);
      await for (final child in stagingRoot.list()) {
        if (p.normalize(child.absolute.path) != p.normalize(stage.path)) {
          await child.delete(recursive: true);
        }
      }
      await stage.create();
      _checkCancelled();
      for (final descriptor in manifest.files) {
        await _preparePartial(stage, manifest, descriptor);
      }
      _received = await _savedBytes(stage, manifest);
      if (await freeBytes(stage.path) < _total - _received + diskReserveBytes) {
        throw const ModelDownloadFailure(
          ModelDownloadErrorCode.noSpace,
          'Недостаточно свободного места.',
          stage: 'storage',
        );
      }
      _emit(ModelDownloadPhase.downloading);
      for (final descriptor in manifest.files) {
        _checkCancelled();
        if (await File(p.join(stage.path, descriptor.name)).exists()) continue;
        await _downloadFile(stage, manifest, descriptor);
      }
      _checkCancelled();
      _emit(ModelDownloadPhase.verifying);
      if (!await verifyModelPackage(stage, manifest)) {
        throw const ModelDownloadFailure(
          ModelDownloadErrorCode.checksum,
          'Файл не прошёл проверку. Повторите загрузку.',
          stage: 'verify',
        );
      }
      _checkCancelled();
      _emit(ModelDownloadPhase.ready);
      return stage;
    } catch (error, stack) {
      if (_cancelled || error is ModelDownloadCancelled) {
        _emit(ModelDownloadPhase.paused);
        throw const ModelDownloadCancelled();
      }
      final failure = classifyDownloadError(error);
      if (!identical(error, _reportedFailure)) {
        _reportedFailure = failure;
        onDiagnostic?.call({
          ...failure.diagnostics(),
          'modelId': manifest.id,
          'revision': manifest.revision,
          'stack': sanitizeDownloadDetails(stack),
        });
      }
      _emit(ModelDownloadPhase.failed);
      throw failure;
    } finally {
      _transport?.close();
      _transport = null;
      _activePackages.remove(lockKey);
      _running = false;
    }
  }

  Future<int> _savedBytes(Directory stage, ModelManifest manifest) async {
    var count = 0;
    for (final f in manifest.files) {
      final complete = File(p.join(stage.path, f.name));
      final part = File('${complete.path}.part');
      if (await complete.exists()) {
        count += min(await complete.length(), f.size);
      } else if (await part.exists()) {
        count += min(await part.length(), f.size);
      }
    }
    return count;
  }

  File _meta(File part) => File('${part.path}.json');
  Future<Map<String, dynamic>> _metadata(File part) async {
    try {
      final decoded = jsonDecode(await _meta(part).readAsString());
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  bool _matches(
    Map<String, dynamic> meta,
    ModelManifest model,
    ModelFile file,
  ) =>
      meta['model'] == model.id &&
      meta['revision'] == model.revision &&
      meta['file'] == file.name &&
      meta['size'] == file.size &&
      meta['sha256'] == file.checksum;
  Future<void> _saveMeta(
    File part,
    ModelManifest model,
    ModelFile file, {
    String? etag,
    String? modified,
  }) async {
    final previous = await _metadata(part);
    final temp = File('${_meta(part).path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'version': 1,
        'model': model.id,
        'revision': model.revision,
        'file': file.name,
        'size': file.size,
        'sha256': file.checksum,
        'savedBytes': await part.exists() ? await part.length() : 0,
        if (etag ?? previous['etag'] case final String value) 'etag': value,
        if (modified ?? previous['lastModified'] case final String value)
          'lastModified': value,
      }),
      flush: true,
    );
    await temp.rename(_meta(part).path);
  }

  Future<void> _preparePartial(
    Directory stage,
    ModelManifest model,
    ModelFile file,
  ) async {
    final target = File(p.join(stage.path, file.name));
    final part = File('${target.path}.part');
    if (await target.exists()) {
      if (await verifyModelFile(target, file)) return;
      await target.delete();
    }
    if (await part.exists()) {
      final meta = await _metadata(part);
      // v141 partials had no sidecar, but their packageKey already binds every
      // expected hash/revision. Adopt those once; reject conflicting sidecars.
      if (meta.isNotEmpty && !_matches(meta, model, file) ||
          await part.length() > file.size) {
        await part.delete();
      } else if (await part.length() == file.size) {
        if (await verifyModelFile(part, file)) {
          await part.rename(target.path);
          if (await _meta(part).exists()) await _meta(part).delete();
          return;
        }
        await part.delete();
      }
    }
    if (await part.exists()) await _saveMeta(part, model, file);
  }

  Future<void> _downloadFile(
    Directory stage,
    ModelManifest model,
    ModelFile file,
  ) async {
    final target = File(p.join(stage.path, file.name));
    final part = File('${target.path}.part');
    for (var attempt = 1; attempt <= retryPolicy.maxAttempts; attempt++) {
      _attempt = attempt;
      _retryAt = null;
      _checkCancelled();
      final watch = Stopwatch()..start();
      String? host;
      var phase = 'connect';
      try {
        _received = await _savedBytes(stage, model);
        _emit(ModelDownloadPhase.downloading);
        var offset = await part.exists() ? await part.length() : 0;
        final metadata = await _metadata(part);
        _transport = _transportFactory();
        if (_transport case final ModelValidatorTransport resumable) {
          final etag = metadata['etag'] as String?;
          final modified = metadata['lastModified'] as String?;
          resumable.setValidator(
            etag != null && !etag.startsWith('W/') ? etag : modified,
          );
        }
        final response = await _cancellable(
          _transport!.get(file.url, offset: offset),
        );
        host = response.host;
        phase = 'headers';
        _checkCancelled();
        if (response.status == 416) {
          if (await part.exists() && await verifyModelFile(part, file)) {
            await part.rename(target.path);
            return;
          }
          // A partial that the origin refuses to range can only restart;
          // keeping this offset forever would trap every subsequent retry.
          if (await part.exists()) await part.delete();
          if (await _meta(part).exists()) await _meta(part).delete();
          throw ModelDownloadFailure(
            ModelDownloadErrorCode.invalidRange,
            'Источник не смог продолжить загрузку. Повторите её.',
            status: 416,
            stage: phase,
            host: host,
            retryable: true,
          );
        }
        if (response.status != 200 && response.status != 206) {
          throw _httpFailure(response);
        }
        if ((response.contentType?.contains('html') ?? false) ||
            response.contentType == 'application/json' &&
                !file.name.endsWith('.json')) {
          throw const ModelDownloadFailure(
            ModelDownloadErrorCode.invalidPayload,
            'Источник вернул сообщение вместо файла модели.',
            stage: 'headers',
          );
        }
        if (response.contentEncoding != null &&
            response.contentEncoding != 'identity') {
          throw const ModelDownloadFailure(
            ModelDownloadErrorCode.invalidResponse,
            'Источник вернул неподдерживаемый формат передачи файла.',
            stage: 'headers',
          );
        }
        if (response.status == 206) {
          final range = RegExp(
            r'^bytes (\d+)-(\d+)/(\d+)$',
          ).firstMatch(response.contentRange ?? '');
          if (range == null ||
              int.parse(range[1]!) != offset ||
              int.parse(range[2]!) != file.size - 1 ||
              int.parse(range[3]!) != file.size) {
            throw const ModelDownloadFailure(
              ModelDownloadErrorCode.invalidRange,
              'Источник вернул некорректный диапазон файла.',
              stage: 'headers',
            );
          }
          final oldEtag = metadata['etag'];
          if (offset > 0 &&
              oldEtag != null &&
              response.etag != null &&
              oldEtag != response.etag) {
            throw const ModelDownloadFailure(
              ModelDownloadErrorCode.invalidRange,
              'Файл на источнике изменился. Загрузите его заново.',
              stage: 'headers',
            );
          }
        } else if (offset > 0) {
          _received -= offset;
          offset = 0;
        }
        if (response.contentLength >= 0 &&
            response.contentLength != file.size - offset) {
          throw const ModelDownloadFailure(
            ModelDownloadErrorCode.invalidResponse,
            'Размер файла не совпадает с проверенным пакетом.',
            stage: 'headers',
          );
        }
        final sink = await part.open(
          mode: offset == 0 ? FileMode.write : FileMode.append,
        );
        if (offset == 0 && await _meta(part).exists()) {
          // A 200 restart establishes new validators, never inherit an ETag
          // from the abandoned response when the new one omits it.
          await _meta(part).delete();
        }
        final iterator = StreamIterator(response.body);
        var written = offset;
        phase = 'body';
        try {
          await _saveMeta(
            part,
            model,
            file,
            etag: response.etag,
            modified: response.lastModified,
          );
          var lastMetadata = 0;
          while (await _cancellable(iterator.moveNext())) {
            _checkCancelled();
            final chunk = iterator.current;
            if (written + chunk.length > file.size) {
              throw const ModelDownloadFailure(
                ModelDownloadErrorCode.invalidResponse,
                'Файл больше ожидаемого размера.',
                stage: 'body',
              );
            }
            phase = 'write';
            await _writeChunk(sink, chunk);
            phase = 'body';
            written += chunk.length;
            _received += chunk.length;
            _emit(ModelDownloadPhase.downloading);
            if (written - lastMetadata >= 1024 * 1024) {
              await _saveMeta(part, model, file);
              lastMetadata = written;
            }
          }
          if (written != file.size) {
            throw const ModelDownloadFailure(
              ModelDownloadErrorCode.connectionClosed,
              'Загрузка прервалась. Можно продолжить.',
              retryable: true,
              stage: 'body',
            );
          }
        } finally {
          try {
            await iterator.cancel();
          } finally {
            try {
              await sink.flush();
            } finally {
              await sink.close();
            }
          }
          await _saveMeta(
            part,
            model,
            file,
            etag: response.etag,
            modified: response.lastModified,
          );
        }
        _checkCancelled();
        phase = 'verify';
        _emit(ModelDownloadPhase.verifying);
        if (!await verifyModelFile(part, file)) {
          await part.delete();
          _received = await _savedBytes(stage, model);
          throw const ModelDownloadFailure(
            ModelDownloadErrorCode.checksum,
            'Файл не прошёл проверку. Повторите загрузку.',
            stage: 'verify',
          );
        }
        _checkCancelled();
        await part.rename(target.path);
        if (await _meta(part).exists()) await _meta(part).delete();
        return;
      } catch (error, stack) {
        if (_cancelled || error is ModelDownloadCancelled) {
          throw const ModelDownloadCancelled();
        }
        _received = await _savedBytes(stage, model);
        final failure = classifyDownloadError(
          error,
          stage: phase,
        ).withContext(host: host, attempt: attempt, savedBytes: _received);
        _reportedFailure = failure;
        onDiagnostic?.call({
          ...failure.diagnostics(),
          'modelId': model.id,
          'revision': model.revision,
          'repo': model.source,
          'file': file.name,
          'durationMs': watch.elapsedMilliseconds,
          'stack': sanitizeDownloadDetails(stack),
        });
        if (!failure.retryable || attempt >= retryPolicy.maxAttempts) {
          throw failure;
        }
        final suggested = failure.retryAt?.difference(DateTime.now());
        if (suggested != null && suggested > retryPolicy.maxServerWait) {
          throw failure;
        }
        final delay = suggested != null && suggested > Duration.zero
            ? suggested
            : retryPolicy.delay(attempt, _random());
        _retryAt = DateTime.now().add(delay);
        _emit(ModelDownloadPhase.retrying);
        _transport?.close();
        _transport = null;
        await _wait(delay);
      } finally {
        _transport?.close();
        _transport = null;
      }
    }
  }

  ModelDownloadFailure _httpFailure(ModelResponse response) {
    final status = response.status;
    final code = switch (status) {
      401 => ModelDownloadErrorCode.unauthorized,
      403 => ModelDownloadErrorCode.forbidden,
      404 => ModelDownloadErrorCode.notFound,
      429 => ModelDownloadErrorCode.rateLimited,
      _ when status >= 500 => ModelDownloadErrorCode.serverUnavailable,
      _ => ModelDownloadErrorCode.http,
    };
    DateTime? retryAt;
    if (response.retryAfter case final String value) {
      final seconds = int.tryParse(value);
      if (seconds != null && seconds >= 0) {
        retryAt = DateTime.now().add(Duration(seconds: seconds));
      } else {
        try {
          retryAt = HttpDate.parse(value);
        } catch (_) {}
      }
    }
    return ModelDownloadFailure(
      code,
      status == 429
          ? 'Источник временно ограничил загрузки. Можно продолжить позже.'
          : status == 401
          ? 'Источник требует авторизацию. Выберите доступную публичную модель.'
          : status == 404
          ? 'Файл модели не найден на источнике.'
          : status == 403
          ? 'Источник временно не разрешил загрузку. Можно повторить.'
          : 'Источник модели временно недоступен.',
      retryable: status == 403 || status == 429 || status >= 500,
      stage: 'headers',
      status: status,
      host: response.host,
      retryAt: retryAt,
    );
  }
}

Future<bool> verifyModelFile(File file, ModelFile descriptor) =>
    Isolate.run(() async {
      if (!await file.exists() || await file.length() != descriptor.size) {
        return false;
      }
      final handle = await file.open();
      late List<int> prefix;
      try {
        prefix = await handle.read(256);
      } finally {
        await handle.close();
      }
      final text = utf8
          .decode(prefix, allowMalformed: true)
          .trimLeft()
          .toLowerCase();
      if (text.startsWith('<!doctype html') ||
          text.startsWith('<html') ||
          text.startsWith('version https://git-lfs.github.com/spec/')) {
        return false;
      }
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == descriptor.checksum;
    });
Future<bool> verifyModelPackage(
  Directory directory,
  ModelManifest manifest,
) async {
  for (final descriptor in manifest.files) {
    if (!await verifyModelFile(
      File(p.join(directory.path, descriptor.name)),
      descriptor,
    )) {
      return false;
    }
  }
  return true;
}
