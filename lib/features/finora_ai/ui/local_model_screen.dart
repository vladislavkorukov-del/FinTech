import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/widgets/common.dart' show confirm;
import '../local_model/local_assistant.dart';
import '../local_model/model_download.dart';
import '../local_model/model_manifest.dart';
import '../local_model/model_store.dart';
import '../../../services/user_error.dart';

class LocalModelScreen extends StatefulWidget {
  const LocalModelScreen({super.key, this.assistant});
  final LocalAssistant? assistant;
  @override
  State<LocalModelScreen> createState() => _LocalModelScreenState();
}

class _LocalModelScreenState extends State<LocalModelScreen> {
  late final assistant = widget.assistant ?? LocalAssistant.instance;
  String? _actionError;
  @override
  void initState() {
    super.initState();
    assistant.ready();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _actionError = null);
    try {
      await action();
    } on ModelDownloadCancelled {
      /* Explicit cancellation is not an error. */
    } catch (e) {
      if (mounted) setState(() => _actionError = userErrorMessage(e));
    }
  }

  static String _stateLabel(ModelInstallState state) => switch (state) {
    ModelInstallState.notInstalled => 'Не установлена',
    ModelInstallState.downloading => 'Загружается',
    ModelInstallState.retrying => 'Повторная попытка',
    ModelInstallState.paused => 'Загрузка приостановлена',
    ModelInstallState.verifying => 'Проверяется',
    ModelInstallState.installed => 'Установлена и проверена',
    ModelInstallState.enabled => 'Включена',
    ModelInstallState.error => 'Ошибка — базовый помощник доступен',
    ModelInstallState.removing => 'Удаляется',
  };

  String _size(int bytes) => '${(bytes / 1000000).toStringAsFixed(1)} МБ';

  Future<void> _download(ModelManifest model) async {
    final sure = await confirm(
      context,
      'Скачать ${model.label}?',
      '${_size(model.downloadBytes)} из Hugging Face. Это размер файлов, не расход оперативной памяти. Сообщения и финансовые данные не отправляются.',
    );
    if (sure) await _run(() => assistant.download(model));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Локальная модель')),
    body: ListenableBuilder(
      listenable: assistant,
      builder: (context, _) {
        final store = assistant.store;
        if (!assistant.supported) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Локальная Qwen доступна на Android arm64. Базовый помощник работает без неё.',
            ),
          );
        }
        if (store == null) {
          return Center(
            child: assistant.error == null
                ? const CircularProgressIndicator()
                : Text(assistant.error!),
          );
        }
        final progress = store.progress;
        final installed = store.installedModel;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text(
              'Экспериментальная Qwen · CPU',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Разговоры и понимание формулировок на телефоне. Расчёты выполняет Finora. Модель необязательна; без неё доступны базовый помощник, классификация и учёт. Интернет нужен только для скачивания.',
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              key: const ValueKey('local-model-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Использовать локальную модель'),
              subtitle: Text(
                installed == null
                    ? 'Не установлена. Переключатель недоступен.'
                    : '${installed.label} · ${assistant.enabled ? (assistant.runtimeLoaded ? 'runtime загружен' : 'загрузится при запросе') : 'выключена'}',
              ),
              value: installed != null && assistant.enabled,
              onChanged: installed == null || assistant.busy
                  ? null
                  : (v) => _run(() => assistant.setEnabled(v)),
            ),
            Text(
              _stateLabel(store.state),
              key: const ValueKey('local-model-state'),
            ),
            if (assistant.error != null ||
                store.error != null ||
                _actionError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  assistant.error ?? store.error ?? _actionError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (assistant.busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: store.state == ModelInstallState.verifying
                    ? null
                    : progress?.fraction,
              ),
              const SizedBox(height: 8),
              Text(
                progress == null
                    ? 'Остановка модели…'
                    : '${_stateLabel(store.state)}: ${_size(progress.receivedBytes)} / ${_size(progress.totalBytes)}${progress.attempt > 1 ? ' · попытка ${progress.attempt}/${progress.maxAttempts}' : ''}',
              ),
              TextButton(
                onPressed: store.busy ? store.pauseDownload : null,
                child: const Text('Приостановить'),
              ),
            ],
            if (store.canResume) ...[
              const SizedBox(height: 12),
              Text(
                '${store.downloadModel!.label}: сохранено ${_size(store.savedDownloadBytes)} из ${_size(store.downloadModel!.downloadBytes)}',
              ),
              FilledButton(
                onPressed: assistant.busy
                    ? null
                    : () => _run(assistant.resumeDownload),
                child: Text(
                  store.savedDownloadBytes > 0 ? 'Продолжить' : 'Повторить',
                ),
              ),
              TextButton(
                onPressed: assistant.busy
                    ? null
                    : () => _run(assistant.discardDownload),
                child: const Text('Отменить и удалить загрузку'),
              ),
            ],
            for (final model in store.catalog) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_size(model.downloadBytes)} · ${model.quantization}\n${model.runtime} · ${model.license}\nДля загрузки нужно свободное место под недостающие файлы и 64 МБ запаса. Это не расход RAM.',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        model.id.contains('0-8') || model.label.contains('0.8')
                            ? 'Облегчённый кандидат. Меньше файлов и памяти, качество ответов может быть ниже.'
                            : 'Стандартный кандидат. Требует больше памяти; скорость на вашем телефоне нужно проверить.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed:
                            assistant.busy ||
                                installed?.packageKey == model.packageKey
                            ? null
                            : () => _download(model),
                        child: Text(
                          installed?.packageKey == model.packageKey
                              ? 'Установлена'
                              : 'Скачать',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (installed != null || store.hasModelFiles) ...[
              const SizedBox(height: 16),
              if (installed != null)
                Text(
                  'Ревизия: ${installed.revision}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              TextButton.icon(
                onPressed: assistant.busy
                    ? null
                    : () async {
                        if (await confirm(
                          context,
                          'Удалить модель?',
                          'Диалоги, персональная память и финансовые данные останутся.',
                        )) {
                          await _run(assistant.remove);
                        }
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Удалить модель'),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Работа на Samsung Galaxy A56 8 ГБ пока не измерена. При нехватке памяти, ошибке или отмене используется базовый режим. Голосовой ввод сохраняет существующие настройки распознавания Android.',
            ),
          ],
        );
      },
    ),
  );
}
