import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'model_download.dart';
import 'model_manifest.dart';
import 'assistant_diagnostics.dart';
import '../../../services/user_error.dart';

enum ModelInstallState {
  notInstalled,
  downloading,
  retrying,
  paused,
  verifying,
  installed,
  enabled,
  error,
  removing,
}

/// Model files/settings are deliberately separate from finance, chat history and
/// personal memory. Changing/removing a model cannot clear those repositories.
/// The caller must stop/unload the runtime before remove or replacement.
class ModelStore extends ChangeNotifier {
  ModelStore({
    required this.root,
    required List<ModelManifest> catalog,
    required this.freeBytes,
    ModelTransport Function()? transport,
  }) : catalog = List.unmodifiable(catalog),
       _transportFactory = transport;

  static Future<ModelStore> open({
    Future<int> Function(String path)? freeBytes,
  }) async {
    final support = await getApplicationSupportDirectory();
    final json =
        jsonDecode(await rootBundle.loadString('assets/ai/local_models.json'))
            as Map<String, dynamic>;
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Версия манифеста модели не поддерживается');
    }
    final store = ModelStore(
      root: Directory(p.join(support.path, 'finora_local_models')),
      catalog: (json['models'] as List)
          .map(
            (m) => ModelManifest.fromJson(Map<String, dynamic>.from(m as Map)),
          )
          .toList(),
      freeBytes:
          freeBytes ??
          (path) async {
            final result = await const MethodChannel(
              'finora/local_llm',
            ).invokeMapMethod<String, dynamic>('storage', {'path': path});
            final available = result?['freeBytes'];
            if (available is! int || available < 0) {
              throw const ModelDeliveryException(
                'Не удалось проверить свободное место',
              );
            }
            return available;
          },
    );
    await store.ready();
    return store;
  }

  final Directory root;
  final List<ModelManifest> catalog;
  final Future<int> Function(String path) freeBytes;
  final ModelTransport Function()? _transportFactory;
  ModelManifest? _installed;
  bool _enabled = false, _busy = false, _disposed = false;
  bool _cancelRequested = false;
  ModelInstallState _state = ModelInstallState.notInstalled;
  ModelManifest? _downloadModel;
  int _savedDownloadBytes = 0;
  bool _retainedFiles = false;
  String? _error;
  ModelDownloadProgress? _progress;
  ModelDownloader? _downloader;
  Future<void>? _ready;

  ModelInstallState get state => _state;
  ModelManifest? get downloadModel => _downloadModel;
  bool get canResume => !_busy && _downloadModel != null;
  int get savedDownloadBytes => _savedDownloadBytes;
  ModelManifest? get installedModel => _installed;
  ModelManifest? get installedManifest => _installed;
  bool get enabled => _enabled;
  bool get busy => _busy;
  bool get hasModelFiles => _installed != null || _retainedFiles;
  String? get error => _error;
  ModelDownloadProgress? get progress => _progress;
  String? get installedPath => _installed == null
      ? null
      : p.join(root.path, 'models', _installed!.packageKey);

  File get _settings => File(p.join(root.path, 'settings.json'));
  File get _transfer => File(p.join(root.path, 'transfer.json'));

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> ready() => _ready ??= _load();

  Future<void> _load() async {
    await root.create(recursive: true);
    if (await _settings.exists()) {
      try {
        final json =
            jsonDecode(await _settings.readAsString()) as Map<String, dynamic>;
        if (json['schemaVersion'] != 1) {
          throw const FormatException(
            'Версия настроек модели не поддерживается',
          );
        }
        if (json['installed'] != null) {
          final manifest = ModelManifest.fromJson(
            Map<String, dynamic>.from(json['installed'] as Map),
          );
          // Never trust a persisted checksum/runtime as a new source of
          // authority. Only packages pinned by this app version may load.
          if (!catalog.any(
            (known) => known.packageKey == manifest.packageKey,
          )) {
            throw const FormatException('Пакет модели отсутствует в каталоге');
          }
          final directory = Directory(
            p.join(root.path, 'models', manifest.packageKey),
          );
          if (await verifyModelPackage(directory, manifest)) {
            _installed = manifest;
            _enabled = json['enabled'] == true;
          } else {
            _error = 'Файлы модели повреждены. Удалите её и скачайте заново.';
          }
        }
      } on Object {
        // Bad optional-model state must not make Finance preferences invalid.
        _error =
            'Настройки локальной модели повреждены. Скачайте модель заново.';
      }
    }
    // A crash between package rename and pointer replacement can leave an
    // orphan. Keep the referenced package, never remove the last working one.
    // If the pointer is damaged, retain files for explicit user deletion.
    if (_error == null) await _cleanUnreferencedModels();
    final models = Directory(p.join(root.path, 'models'));
    _retainedFiles = await models.exists() && !await models.list().isEmpty;
    _state = _error != null
        ? ModelInstallState.error
        : _enabled
        ? ModelInstallState.enabled
        : _installed != null
        ? ModelInstallState.installed
        : ModelInstallState.notInstalled;
    await _recoverTransfer();
    _notify();
  }

  Future<void> _persistTransfer() async {
    final model = _downloadModel;
    if (model == null) return;
    final tmp = File('${_transfer.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'packageKey': model.packageKey,
        'modelId': model.id,
        'revision': model.revision,
        'phase': _state.name,
      }),
      flush: true,
    );
    await tmp.rename(_transfer.path);
  }

  Future<void> _recoverTransfer() async {
    ModelManifest? model;
    if (await _transfer.exists()) {
      try {
        final json = jsonDecode(await _transfer.readAsString()) as Map;
        model = catalog
            .where((m) => m.packageKey == json['packageKey'])
            .firstOrNull;
      } catch (_) {
        /* Recover actual app-owned stage files below. */
      }
    }
    // Also migrate interrupted build141 downloads, which had no transfer file.
    model ??= catalog
        .where(
          (m) => Directory(
            p.join(root.path, 'downloads', m.packageKey),
          ).existsSync(),
        )
        .firstOrNull;
    if (model == null) return;
    final stage = Directory(p.join(root.path, 'downloads', model.packageKey));
    if (!await stage.exists()) {
      if (await _transfer.exists()) await _transfer.delete();
      return;
    }
    var bytes = 0;
    for (final descriptor in model.files) {
      final complete = File(p.join(stage.path, descriptor.name));
      final partial = File('${complete.path}.part');
      final file = await complete.exists() ? complete : partial;
      if (await file.exists()) {
        final size = await file.length();
        if (size <= descriptor.size) bytes += size;
      }
    }
    _downloadModel = model;
    _savedDownloadBytes = bytes;
    _progress = ModelDownloadProgress(
      bytes,
      model.downloadBytes,
      ModelDownloadPhase.paused,
    );
    _state = ModelInstallState.paused;
  }

  Future<void> _save(
    ModelManifest? installed,
    bool enabled, {
    bool cancellable = false,
  }) async {
    final temporary = File('${_settings.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'enabled': enabled,
        'installed': installed?.toJson(),
      }),
      flush: true,
    );
    // Android/Linux rename replaces the pointer atomically. A crash never
    // exposes half a JSON document or an unverified staging directory.
    if (cancellable && _cancelRequested) {
      await temporary.delete();
      throw const ModelDownloadCancelled();
    }
    await temporary.rename(_settings.path);
  }

  Future<void> download(ModelManifest manifest) async {
    await ready();
    if (_busy) throw const ModelDeliveryException('Дождитесь текущей операции');
    if (!catalog.any((m) => m.packageKey == manifest.packageKey)) {
      throw const ModelDeliveryException(
        'Эта модель отсутствует в каталоге Finora',
      );
    }
    _busy = true;
    _cancelRequested = false;
    _savedDownloadBytes = _downloadModel?.packageKey == manifest.packageKey
        ? _savedDownloadBytes
        : 0;
    _downloadModel = manifest;
    _state = ModelInstallState.downloading;
    _error = null;
    _progress = ModelDownloadProgress(
      _downloadModel?.packageKey == manifest.packageKey
          ? _savedDownloadBytes
          : 0,
      manifest.downloadBytes,
      ModelDownloadPhase.downloading,
    );
    _notify();
    final downloader = ModelDownloader(
      stagingRoot: Directory(p.join(root.path, 'downloads')),
      freeBytes: freeBytes,
      transport: _transportFactory,
      onDiagnostic: (event) =>
          AssistantDiagnostics.instance.record('model_download', values: event),
      onProgress: (value) {
        _progress = value;
        _savedDownloadBytes = value.receivedBytes;
        _state = switch (value.phase) {
          ModelDownloadPhase.verifying => ModelInstallState.verifying,
          ModelDownloadPhase.retrying => ModelInstallState.retrying,
          ModelDownloadPhase.paused => ModelInstallState.paused,
          _ => ModelInstallState.downloading,
        };
        _notify();
      },
    );
    _downloader = downloader;
    if (_cancelRequested) downloader.cancel();
    try {
      await _persistTransfer();
      final stage = await downloader.download(manifest);
      final models = Directory(p.join(root.path, 'models'));
      await models.create(recursive: true);
      final destination = Directory(p.join(models.path, manifest.packageKey));
      if (await destination.exists()) {
        if (!await verifyModelPackage(destination, manifest)) {
          // Never replace a currently active directory in-place.
          if (_installed?.packageKey == manifest.packageKey) {
            throw const ModelDeliveryException(
              'Удалите повреждённую модель перед повторной установкой',
            );
          }
          await destination.delete(recursive: true);
          await stage.rename(destination.path);
        } else {
          await stage.delete(recursive: true);
        }
      } else {
        await stage.rename(destination.path);
      }
      // Preserve previous pointer and enabled flag if this write fails.
      await _save(manifest, false, cancellable: true);
      _installed = manifest;
      _retainedFiles = true;
      _enabled = false; // Installation never opts the user into inference.
      _progress = ModelDownloadProgress(
        manifest.downloadBytes,
        manifest.downloadBytes,
        ModelDownloadPhase.ready,
      );
      await _cleanUnreferencedModels();
      _downloadModel = null;
      _savedDownloadBytes = 0;
      _state = ModelInstallState.installed;
      if (await _transfer.exists()) await _transfer.delete();
    } on ModelDownloadCancelled {
      _error = null;
      _state = ModelInstallState.paused;
      _progress = ModelDownloadProgress(
        _savedDownloadBytes,
        manifest.downloadBytes,
        ModelDownloadPhase.paused,
      );
      await _persistTransfer();
      rethrow;
    } catch (error) {
      _error = userErrorMessage(error);
      _state = ModelInstallState.error;
      await _persistTransfer();
      rethrow;
    } finally {
      _downloader = null;
      _busy = false;
      _notify();
    }
  }

  void pauseDownload() {
    cancelDownload();
  }

  Future<void> resumeDownload() async {
    final model = _downloadModel;
    if (model != null) await download(model);
  }

  void cancelDownload() {
    _cancelRequested = true;
    _downloader?.cancel();
  }

  Future<void> discardDownload() async {
    await ready();
    if (_busy) {
      throw const ModelDeliveryException('Сначала приостановите загрузку');
    }
    final downloads = Directory(p.join(root.path, 'downloads'));
    if (await downloads.exists()) await downloads.delete(recursive: true);
    if (await _transfer.exists()) await _transfer.delete();
    _downloadModel = null;
    _savedDownloadBytes = 0;
    _progress = null;
    _error = null;
    _state = _enabled
        ? ModelInstallState.enabled
        : _installed != null
        ? ModelInstallState.installed
        : ModelInstallState.notInstalled;
    _notify();
  }

  Future<void> setEnabled(bool enabled) async {
    await ready();
    if (_busy) throw const ModelDeliveryException('Дождитесь текущей операции');
    if (enabled && _installed == null) {
      throw const ModelDeliveryException('Сначала скачайте модель');
    }
    _busy = true;
    try {
      await _save(_installed, enabled);
      _enabled = enabled;
      _state = enabled
          ? ModelInstallState.enabled
          : ModelInstallState.installed;
      _error = null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> removeInstalled() async {
    await ready();
    if (_busy) {
      throw const ModelDeliveryException('Сначала остановите скачивание');
    }
    _busy = true;
    _state = ModelInstallState.removing;
    _notify();
    try {
      // Disable before deleting weights. No financial/personal files are here.
      await _save(null, false);
      _installed = null;
      _enabled = false;
      await _cleanUnreferencedModels();
      _retainedFiles = false;
      final downloads = Directory(p.join(root.path, 'downloads'));
      if (await downloads.exists()) await downloads.delete(recursive: true);
      _progress = null;
      _downloadModel = null;
      _savedDownloadBytes = 0;
      if (await _transfer.exists()) await _transfer.delete();
      _state = ModelInstallState.notInstalled;
      _error = null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _cleanUnreferencedModels() async {
    final models = Directory(p.join(root.path, 'models'));
    if (!await models.exists()) return;
    await for (final child in models.list()) {
      if (p.basename(child.path) != _installed?.packageKey) {
        await child.delete(recursive: true);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancelDownload();
    super.dispose();
  }
}
