import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:share_plus/share_plus.dart';

import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/widgets/common.dart' show showError;
import '../local_model/assistant_diagnostics.dart';
import '../local_model/local_assistant.dart';

class LocalModelDiagnosticsScreen extends StatefulWidget {
  const LocalModelDiagnosticsScreen({super.key});
  @override
  State<LocalModelDiagnosticsScreen> createState() =>
      _LocalModelDiagnosticsScreenState();
}

class _LocalModelDiagnosticsScreenState
    extends State<LocalModelDiagnosticsScreen> {
  final diagnostics = AssistantDiagnostics.instance;
  final assistant = LocalAssistant.instance;
  Map<String, Object?> metrics = {};
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      await assistant.ready();
      final next = await assistant.runtime.diagnostics();
      if (mounted) {
        setState(() {
          metrics = next;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Нативная диагностика недоступна на этой платформе.',
        );
      }
    }
  }

  Future<void> _export() async {
    setState(() => busy = true);
    try {
      await _refresh();
      final model = assistant.store?.installedModel;
      final file = await diagnostics.export(
        metadata: {
          'enabled': assistant.enabled,
          if (model != null) ...model.toJson(),
          'contextTokens': 2048,
          'maxNewTokens': 256,
          'backend': 'CPU',
        },
        runtime: metrics,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Диагностика локального AI Finora',
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Диагностика локального AI'),
      actions: [
        IconButton(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          tooltip: 'Обновить',
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: diagnostics,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(assistant.label, style: Theme.of(context).textTheme.titleLarge),
          const Text('MNN 3.6.2 · CPU · контекст 2048 · ответ до 256 токенов'),
          if (error != null) Text(error!),
          const SizedBox(height: 16),
          for (final e in metrics.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SelectableText('${e.key}: ${e.value}'),
            ),
          const Text(
            'processPssBytes — память процесса Finora. availableMemoryBytes — доступная память телефона. thermalStatus — системный уровень нагрузки, не температура процессора.',
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Включать видимый текст в экспорт'),
            subtitle: const Text(
              'По умолчанию выключено. Новые ответы и результаты действий могут содержать личные сведения. Рассуждения модели не собираются.',
            ),
            value: diagnostics.collectText,
            onChanged: diagnostics.setCollectText,
          ),
          FilledButton.icon(
            onPressed: busy ? null : _export,
            icon: const Icon(Icons.ios_share),
            label: const Text('Экспорт диагностики'),
          ),
          TextButton(
            onPressed: diagnostics.clear,
            child: const Text('Очистить события диагностики'),
          ),
          for (final event in diagnostics.records.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${event['event']}'),
              subtitle: Text('${event['at']}'),
              trailing: event['totalMs'] == null
                  ? null
                  : Text('${event['totalMs']} мс'),
            ),
        ],
      ),
    ),
  );
}
