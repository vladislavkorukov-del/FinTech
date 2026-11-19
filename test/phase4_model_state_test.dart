import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:finora/features/finora_ai/local_model/local_assistant.dart';
import 'package:finora/features/finora_ai/local_model/local_runtime.dart';
import 'package:finora/features/finora_ai/local_model/model_download.dart';
import 'package:finora/features/finora_ai/local_model/model_manifest.dart';
import 'package:finora/features/finora_ai/local_model/model_store.dart';
import 'package:finora/features/finora_ai/ui/local_model_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Bytes implements ModelTransport {
  _Bytes(this.bytes);
  final List<int> bytes;
  @override
  Future<ModelResponse> get(Uri url, {required int offset}) async =>
      ModelResponse(
        status: offset > 0 ? 206 : 200,
        contentLength: bytes.length - offset,
        contentRange: offset > 0
            ? 'bytes $offset-${bytes.length - 1}/${bytes.length}'
            : null,
        body: Stream.value(bytes.sublist(offset)),
      );
  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = utf8.encode('synthetic model for state tests; not inference');
  final revision = 'a' * 40;
  final model = ModelManifest(
    id: 'state-test',
    label: 'Синтетическая модель',
    source: 'taobao-mnn/test',
    revision: revision,
    format: 'MNN-LLM',
    quantization: '4-bit',
    license: 'Apache-2.0',
    runtime: 'MNN 3.6.2',
    runtimeRevision: 'b' * 40,
    files: [
      ModelFile(
        name: 'llm.mnn.weight',
        size: bytes.length,
        checksum: sha256.convert(bytes).toString(),
        url: Uri.parse(
          'https://huggingface.co/taobao-mnn/test/resolve/$revision/llm.mnn.weight',
        ),
      ),
    ],
  );
  late Directory root;
  ModelStore store() => ModelStore(
    root: root,
    catalog: [model],
    freeBytes: (_) async => 1 << 30,
    transport: () => _Bytes(bytes),
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('finora-stage1-state-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'build141 partial recovers as paused with actual disk bytes, never installed/enabled',
    () async {
      final stage = Directory('${root.path}/downloads/${model.packageKey}');
      await stage.create(recursive: true);
      await File(
        '${stage.path}/llm.mnn.weight.part',
      ).writeAsBytes(bytes.take(9).toList());
      final first = store();
      await first.ready();
      expect(first.state, ModelInstallState.paused);
      expect(first.savedDownloadBytes, 9);
      expect(first.enabled, isFalse);
      expect(first.installedModel, isNull);
      await first.resumeDownload();
      expect(first.state, ModelInstallState.installed);
      expect(first.enabled, isFalse);
      expect(first.downloadModel, isNull);
      final reopened = store();
      await reopened.ready();
      expect(reopened.installedModel?.id, model.id);
      expect(reopened.enabled, isFalse);
      first.dispose();
      reopened.dispose();
    },
  );

  test(
    'forged enabled flag without a verified package cannot enable inference',
    () async {
      await File('${root.path}/settings.json').writeAsString(
        jsonEncode({'schemaVersion': 1, 'enabled': true, 'installed': null}),
      );
      final s = store();
      await s.ready();
      expect(s.enabled, isFalse);
      expect(s.state, ModelInstallState.notInstalled);
      s.dispose();
    },
  );

  test(
    'discarding staged download preserves installed active model and neighbouring personal files',
    () async {
      final s = store();
      await s.download(model);
      await s.setEnabled(true);
      final memory = File(
        '${root.path}/../${root.uri.pathSegments.where((s) => s.isNotEmpty).last}-memory.json',
      );
      await memory.writeAsString('user data');
      addTearDown(() => memory.delete());
      final stage = Directory('${root.path}/downloads/${model.packageKey}');
      await stage.create(recursive: true);
      await File(
        '${stage.path}/llm.mnn.weight.part',
      ).writeAsBytes(bytes.take(5).toList());
      final reopened = store();
      await reopened.ready();
      await reopened.discardDownload();
      expect(reopened.enabled, isTrue);
      expect(reopened.installedModel?.id, model.id);
      expect(await memory.readAsString(), 'user data');
      s.dispose();
      reopened.dispose();
    },
  );

  testWidgets(
    'failed native initialization leaves switch off with one short inline error',
    (tester) async {
      const channel = MethodChannel('phase4/runtime-state-test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'load') {
              throw PlatformException(
                code: 'local_model',
                message: 'https://cdn.invalid/?Signature=DO_NOT_SHOW',
              );
            }
            return <String, Object?>{};
          });
      final s = store();
      await tester.runAsync(() => s.download(model));
      final runtime = LocalRuntime(channel: channel);
      final assistant = LocalAssistant(
        runtime: runtime,
        openStore: () async => s,
      );
      await tester.runAsync(assistant.ready);
      await tester.runAsync(() async {
        try {
          await assistant.setEnabled(true);
        } catch (_) {}
      });
      expect(s.enabled, isFalse);
      expect(assistant.canGenerate, isFalse);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: LocalModelScreen(assistant: assistant)),
      );
      await tester.pump();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('local-model-enabled')),
            )
            .value,
        isFalse,
      );
      expect(find.textContaining('не запустилась'), findsOneWidget);
      expect(find.textContaining('DO_NOT_SHOW'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(runtime.unload);
      assistant.dispose();
      s.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
