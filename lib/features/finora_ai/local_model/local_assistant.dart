import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'assistant_diagnostics.dart';
import 'local_runtime.dart';
import 'model_manifest.dart';
import 'model_download.dart';
import 'model_store.dart';
import '../../../services/user_error.dart';

/// Single owner of optional model settings and lifecycle; the ledger and
/// classifier never depend on its availability.
class LocalAssistant extends ChangeNotifier with WidgetsBindingObserver {
  LocalAssistant({
    LocalRuntime? runtime,
    Future<ModelStore> Function()? openStore,
  }) : runtime = runtime ?? LocalRuntime.instance,
       _openStore = openStore ?? ModelStore.open;
  static final instance = LocalAssistant();
  final LocalRuntime runtime;
  final Future<ModelStore> Function() _openStore;
  bool _observing = false;
  bool runtimeAvailable = true;
  bool get runtimeLoaded => runtime.loaded;
  ModelStore? store;
  String? error;
  bool changing = false;
  Future<void>? _ready;
  bool get supported => runtime.supported;
  bool get enabled => store?.installedModel != null && store?.enabled == true;
  bool get busy => changing || store?.busy == true;
  bool get canGenerate => enabled && !busy && runtimeAvailable;
  String get label => enabled ? store!.installedModel!.label : 'FinAI 1.0';

  Future<void> ready() => _ready ??= _load();
  Future<void> _load() async {
    if (!supported || kIsWeb) return;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    try {
      store = await _openStore();
      store!.addListener(notifyListeners);
    } catch (_) {
      error =
          'Не удалось открыть настройки локальной модели. Базовый помощник доступен.';
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) => _change(() async {
    await runtime.unload();
    if (value) {
      final path = store!.installedPath;
      if (path == null) {
        throw const FormatException('Сначала скачайте и проверьте модель.');
      }
      // Explicit enabling performs real initialization, not a chat/generation.
      // A failed load must never persist an enabled switch.
      try {
        await runtime.load(path);
        runtimeAvailable = true;
      } catch (_) {
        await store!.setEnabled(false);
        throw const FormatException(
          'Модель установлена, но не запустилась. Можно повторить включение или использовать базовый режим.',
        );
      }
    }
    await store!.setEnabled(value);
    AssistantDiagnostics.instance.record(value ? 'enabled' : 'disabled');
  });

  Future<void> download(ModelManifest model) => _change(() async {
    await runtime.unload();
    await store!.download(model);
    AssistantDiagnostics.instance.record(
      'installed',
      values: {
        'id': model.id,
        'revision': model.revision,
        'bytes': model.downloadBytes,
      },
    );
  });

  Future<void> discardDownload() => _change(() => store!.discardDownload());

  Future<void> remove() => _change(() async {
    await runtime.unload();
    await store!.removeInstalled();
    AssistantDiagnostics.instance.record('removed');
  });

  Future<void> _change(Future<void> Function() action) async {
    if (busy || store == null) return;
    changing = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } on ModelDownloadCancelled {
      AssistantDiagnostics.instance.record('download_cancelled');
      rethrow;
    } catch (e) {
      error = store?.error ?? userErrorMessage(e);
      AssistantDiagnostics.instance.record(
        'model_error',
        values: {'type': e.runtimeType.toString()},
      );
      rethrow;
    } finally {
      changing = false;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (store?.busy == true) store!.pauseDownload();
      unawaited(_release('background'));
    }
  }

  @override
  void didHaveMemoryPressure() => unawaited(_release('memory_pressure'));

  Future<void> resumeDownload() async {
    final model = store?.downloadModel;
    if (model != null) await download(model);
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    store?.removeListener(notifyListeners);
    super.dispose();
  }

  Future<void> _release(String reason) async {
    try {
      await runtime.unload();
      AssistantDiagnostics.instance.record(reason);
    } catch (_) {
      AssistantDiagnostics.instance.record('release_error');
    }
  }
}
