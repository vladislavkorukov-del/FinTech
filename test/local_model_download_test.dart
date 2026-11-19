import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:finora/features/finora_ai/local_model/model_download.dart';
import 'package:finora/features/finora_ai/local_model/model_manifest.dart';
import 'package:finora/features/finora_ai/local_model/model_store.dart';

const _revision = '3208b55b2e3c948016c9d380a697be881a1f12f8';
const _runtime = 'b0239771b07b317a258fbc384683bbd540741406';

ModelManifest _manifest(
  String id,
  Map<String, List<int>> files,
) => ModelManifest(
  id: id,
  label: id,
  source: 'taobao-mnn/test',
  revision: _revision,
  format: 'MNN-LLM',
  quantization: '4-bit',
  license: 'Apache-2.0',
  runtime: 'MNN 3.6.2',
  runtimeRevision: _runtime,
  files: files.entries
      .map(
        (e) => ModelFile(
          name: e.key,
          size: e.value.length,
          checksum: sha256.convert(e.value).toString(),
          url: Uri.parse(
            'https://huggingface.co/taobao-mnn/test/resolve/$_revision/${e.key}',
          ),
        ),
      )
      .toList(),
);

class _Transport implements ModelTransport {
  _Transport(this.respond);
  final Future<ModelResponse> Function(Uri, int) respond;
  bool closed = false;
  final requests = <(Uri, int)>[];
  @override
  Future<ModelResponse> get(Uri url, {required int offset}) {
    requests.add((url, offset));
    return respond(url, offset);
  }

  @override
  void close() => closed = true;
}

ModelResponse _response(
  List<int> bytes,
  int offset, {
  bool ignoreRange = false,
}) => ModelResponse(
  status: offset > 0 && !ignoreRange ? 206 : 200,
  contentLength: bytes.length - (ignoreRange ? 0 : offset),
  contentRange: offset > 0 && !ignoreRange
      ? 'bytes $offset-${bytes.length - 1}/${bytes.length}'
      : null,
  body: Stream.value(ignoreRange ? bytes : bytes.sublist(offset)),
);

void main() {
  late Directory root;
  final payload = <String, List<int>>{
    'config.json': utf8.encode('{"backend_type":"cpu"}'),
    'llm.mnn.weight': List.generate(8192, (i) => i % 251),
  };
  final manifest = _manifest('small', payload);
  Future<int> plenty(String _) async => 1024 * 1024 * 1024;
  _Transport transportFor(Map<String, List<int>> data) => _Transport(
    (url, offset) async => _response(data[p.basename(url.path)]!, offset),
  );

  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('finora-model-test-'),
  );
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'real pinned catalog has exact sizes, checksums and no vision/weights in asset',
    () async {
      final json =
          jsonDecode(await File('assets/ai/local_models.json').readAsString())
              as Map;
      final models = (json['models'] as List)
          .map(
            (m) => ModelManifest.fromJson(Map<String, dynamic>.from(m as Map)),
          )
          .toList();
      expect(models.map((m) => m.id), ['qwen35-08b', 'qwen35-2b']);
      expect(models[0].downloadBytes, 479005820);
      expect(models[1].downloadBytes, 1068999731);
      for (final model in models) {
        expect(model.runtimeRevision, _runtime);
        expect(model.files.any((f) => f.name.startsWith('visual')), false);
        expect(model.files.any((f) => f.name == 'llm.mnn.weight'), true);
        expect(
          model.files.every((f) => f.url.path.contains(model.revision)),
          true,
        );
      }
    },
  );

  test(
    'verifies complete package before returning it; reports actual byte progress',
    () async {
      final progress = <ModelDownloadProgress>[];
      final transport = transportFor(payload);
      final downloader = ModelDownloader(
        stagingRoot: root,
        freeBytes: plenty,
        transport: () => transport,
        onProgress: progress.add,
      );
      final installed = await downloader.download(manifest);
      expect(await verifyModelPackage(installed, manifest), true);
      expect(progress.last.receivedBytes, manifest.downloadBytes);
      expect(progress.last.phase, ModelDownloadPhase.ready);
      expect(progress.every((p) => p.receivedBytes <= p.totalBytes), true);
      expect(transport.closed, true);
    },
  );

  test(
    'interruption preserves bounded partial; retry uses exact Range and hash',
    () async {
      final data = payload['llm.mnn.weight']!;
      final single = _manifest('resume', {'llm.mnn.weight': data});
      final interrupted = _Transport(
        (url, offset) async => ModelResponse(
          status: 200,
          contentLength: data.length,
          body: Stream<List<int>>.multi((controller) {
            controller.add(data.sublist(0, 1000));
            controller.addError(const SocketException('interrupted'));
            controller.close();
          }),
        ),
      );
      await expectLater(
        ModelDownloader(
          stagingRoot: root,
          freeBytes: plenty,
          transport: () => interrupted,
        ).download(single),
        throwsA(isA<ModelDownloadFailure>()),
      );
      final part = File(
        p.join(root.path, single.packageKey, 'llm.mnn.weight.part'),
      );
      expect(await part.length(), 1000);
      final resumed = transportFor({'llm.mnn.weight': data});
      final directory = await ModelDownloader(
        stagingRoot: root,
        freeBytes: plenty,
        transport: () => resumed,
      ).download(single);
      expect(resumed.requests.single.$2, 1000);
      expect(await verifyModelPackage(directory, single), true);
    },
  );

  test(
    'ignored Range restarts instead of appending full file to partial',
    () async {
      final data = payload['llm.mnn.weight']!;
      final single = _manifest('ignored-range', {'llm.mnn.weight': data});
      final stage = Directory(p.join(root.path, single.packageKey));
      await stage.create();
      await File(
        p.join(stage.path, 'llm.mnn.weight.part'),
      ).writeAsBytes(data.sublist(0, 123));
      final transport = _Transport(
        (url, offset) async => _response(data, offset, ignoreRange: true),
      );
      final directory = await ModelDownloader(
        stagingRoot: root,
        freeBytes: plenty,
        transport: () => transport,
      ).download(single);
      expect(transport.requests.single.$2, 123);
      expect(await verifyModelPackage(directory, single), true);
    },
  );

  test('wrong checksum is rejected and poisoned partial removed', () async {
    final transport = _Transport(
      (url, offset) async => _response(
        List.filled(payload[p.basename(url.path)]!.length, 0),
        offset,
      ),
    );
    await expectLater(
      ModelDownloader(
        stagingRoot: root,
        freeBytes: plenty,
        transport: () => transport,
      ).download(manifest),
      throwsA(isA<ModelDeliveryException>()),
    );
    expect(
      await File(
        p.join(root.path, manifest.packageKey, 'config.json'),
      ).exists(),
      false,
    );
    expect(
      await File(
        p.join(root.path, manifest.packageKey, 'config.json.part'),
      ).exists(),
      false,
    );
  });

  for (final text in [
    '<!DOCTYPE html><html>failure</html>',
    'version https://git-lfs.github.com/spec/v1\noid sha256:abc',
  ]) {
    test(
      'rejects HTML/LFS pointer even if a forged manifest agrees with its hash: ${text.substring(0, 10)}',
      () async {
        final bytes = utf8.encode(text);
        final invalid = _manifest('pointer', {'llm.mnn.weight': bytes});
        await expectLater(
          ModelDownloader(
            stagingRoot: root,
            freeBytes: plenty,
            transport: () => transportFor({'llm.mnn.weight': bytes}),
          ).download(invalid),
          throwsA(isA<ModelDeliveryException>()),
        );
      },
    );
  }

  test(
    'insufficient disk fails before HTTP and never creates an installation',
    () async {
      var network = false;
      await expectLater(
        ModelDownloader(
          stagingRoot: root,
          freeBytes: (_) async => 10,
          transport: () {
            network = true;
            return transportFor(payload);
          },
        ).download(manifest),
        throwsA(isA<ModelDeliveryException>()),
      );
      expect(network, false);
    },
  );

  test('rejects mismatched range without appending or activating it', () async {
    final data = payload['llm.mnn.weight']!;
    final single = _manifest('bad-range', {'llm.mnn.weight': data});
    final directory = Directory(p.join(root.path, single.packageKey));
    await directory.create();
    final part = File(p.join(directory.path, 'llm.mnn.weight.part'));
    await part.writeAsBytes(data.sublist(0, 100));
    final transport = _Transport(
      (url, offset) async => ModelResponse(
        status: 206,
        contentRange: 'bytes 0-${data.length - 1}/${data.length}',
        body: Stream.value(data),
      ),
    );
    await expectLater(
      ModelDownloader(
        stagingRoot: root,
        freeBytes: plenty,
        transport: () => transport,
      ).download(single),
      throwsA(isA<ModelDeliveryException>()),
    );
    expect(await part.length(), 100);
  });

  test(
    'cancel never returns verified activation and next choice removes other partial package',
    () async {
      final data = payload['llm.mnn.weight']!;
      final single = _manifest('cancel', {'llm.mnn.weight': data});
      late ModelDownloader downloader;
      final transport = _Transport(
        (url, offset) async => ModelResponse(
          status: 200,
          contentLength: data.length,
          body: Stream.fromIterable([data.sublist(0, 100), data.sublist(100)]),
        ),
      );
      downloader = ModelDownloader(
        stagingRoot: root,
        freeBytes: plenty,
        transport: () => transport,
        onProgress: (value) {
          if (value.receivedBytes >= 100) downloader.cancel();
        },
      );
      await expectLater(
        downloader.download(single),
        throwsA(isA<ModelDownloadCancelled>()),
      );
      expect(transport.closed, true);
      await ModelDownloader(
        stagingRoot: root,
        freeBytes: plenty,
        transport: () => transportFor(payload),
      ).download(manifest);
      expect(
        await Directory(p.join(root.path, single.packageKey)).exists(),
        false,
      );
    },
  );

  test('wrong length and non-200 HTTP never activate a model', () async {
    for (final response in [
      const ModelResponse(status: 404, body: Stream.empty()),
      ModelResponse(
        status: 200,
        contentLength: 100000,
        body: Stream.value([1, 2]),
      ),
    ]) {
      await expectLater(
        ModelDownloader(
          stagingRoot: root,
          freeBytes: plenty,
          transport: () => _Transport((_, _) async => response),
        ).download(manifest),
        throwsA(isA<ModelDeliveryException>()),
      );
    }
  });

  test(
    'store disabled by default; install requires explicit enable; restart/delete isolated',
    () async {
      final finance = File(p.join(root.path, 'finance.sqlite'));
      final memory = File(p.join(root.path, 'personal_memory.json'));
      await finance.writeAsString('untouched-finance');
      await memory.writeAsString('untouched-memory');
      final modelRoot = Directory(p.join(root.path, 'models-only'));
      ModelStore create() => ModelStore(
        root: modelRoot,
        catalog: [manifest],
        freeBytes: plenty,
        transport: () => transportFor(payload),
      );
      final store = create();
      await store.ready();
      expect(store.enabled, false);
      expect(store.installedModel, null);
      await store.download(manifest);
      expect(store.installedModel?.packageKey, manifest.packageKey);
      expect(store.enabled, false);
      await store.setEnabled(true);
      store.dispose();
      final reopened = create();
      await reopened.ready();
      expect(reopened.enabled, true);
      expect(reopened.installedPath, isNotNull);
      await reopened.removeInstalled();
      expect(reopened.installedModel, null);
      expect(reopened.enabled, false);
      expect(await finance.readAsString(), 'untouched-finance');
      expect(await memory.readAsString(), 'untouched-memory');
      reopened.dispose();
    },
  );

  test(
    'failed replacement keeps installed working model and enabled state',
    () async {
      final secondPayload = {
        'llm.mnn.weight': utf8.encode('new model fixture'),
      };
      final second = _manifest('second', secondPayload);
      var corrupt = false;
      final store = ModelStore(
        root: root,
        catalog: [manifest, second],
        freeBytes: plenty,
        transport: () => _Transport((url, offset) async {
          final data = corrupt
              ? List.filled(secondPayload.values.single.length, 0)
              : payload[p.basename(url.path)]!;
          return _response(data, offset);
        }),
      );
      await store.download(manifest);
      await store.setEnabled(true);
      final oldPath = store.installedPath;
      corrupt = true;
      await expectLater(
        store.download(second),
        throwsA(isA<ModelDeliveryException>()),
      );
      expect(store.installedPath, oldPath);
      expect(store.enabled, true);
      expect(await verifyModelPackage(Directory(oldPath!), manifest), true);
      final reopened = ModelStore(
        root: root,
        catalog: [manifest, second],
        freeBytes: plenty,
      );
      await reopened.ready();
      expect(reopened.installedPath, oldPath);
      expect(reopened.enabled, true);
      store.dispose();
      reopened.dispose();
    },
  );

  test(
    'modified installed weight fails closed at next startup without finance reset',
    () async {
      final store = ModelStore(
        root: root,
        catalog: [manifest],
        freeBytes: plenty,
        transport: () => transportFor(payload),
      );
      await store.download(manifest);
      await store.setEnabled(true);
      await File(
        p.join(store.installedPath!, 'llm.mnn.weight'),
      ).writeAsBytes(List.filled(8192, 0));
      final reopened = ModelStore(
        root: root,
        catalog: [manifest],
        freeBytes: plenty,
      );
      await reopened.ready();
      expect(reopened.enabled, false);
      expect(reopened.installedModel, null);
      expect(reopened.error, contains('повреждены'));
      expect(reopened.hasModelFiles, true);
      expect(await Directory(store.installedPath!).exists(), true);
      await reopened.removeInstalled();
      expect(reopened.hasModelFiles, false);
      expect(await Directory(store.installedPath!).exists(), false);
      store.dispose();
      reopened.dispose();
    },
  );

  test(
    'cancellation after verification cannot replace the active pointer',
    () async {
      final secondPayload = {'llm.mnn.weight': utf8.encode('another model')};
      final second = _manifest('cancel-after-verify', secondPayload);
      var useSecond = false;
      final store = ModelStore(
        root: root,
        catalog: [manifest, second],
        freeBytes: plenty,
        transport: () => transportFor(useSecond ? secondPayload : payload),
      );
      await store.download(manifest);
      await store.setEnabled(true);
      final oldPath = store.installedPath;
      useSecond = true;
      store.addListener(() {
        if (store.progress?.phase == ModelDownloadPhase.ready) {
          store.cancelDownload();
        }
      });
      await expectLater(
        store.download(second),
        throwsA(isA<ModelDownloadCancelled>()),
      );
      expect(store.installedPath, oldPath);
      expect(store.enabled, true);
      final reopened = ModelStore(
        root: root,
        catalog: [manifest, second],
        freeBytes: plenty,
      );
      await reopened.ready();
      expect(reopened.installedPath, oldPath);
      expect(reopened.enabled, true);
      expect(
        await Directory(
          p.join(root.path, 'models', second.packageKey),
        ).exists(),
        false,
      );
      store.dispose();
      reopened.dispose();
    },
  );

  test(
    'malformed optional settings fail closed without changing their original bytes',
    () async {
      await File(p.join(root.path, 'settings.json')).writeAsString('{broken');
      final store = ModelStore(
        root: root,
        catalog: [manifest],
        freeBytes: plenty,
      );
      await store.ready();
      expect(store.enabled, false);
      expect(store.error, contains('повреждены'));
      expect(
        await File(p.join(root.path, 'settings.json')).readAsString(),
        '{broken',
      );
      store.dispose();
    },
  );

  test(
    'persisted manifest cannot authorize an unknown runtime or checksum set',
    () async {
      final store = ModelStore(
        root: root,
        catalog: [manifest],
        freeBytes: plenty,
        transport: () => transportFor(payload),
      );
      await store.download(manifest);
      await store.setEnabled(true);
      final settings = File(p.join(root.path, 'settings.json'));
      final json =
          jsonDecode(await settings.readAsString()) as Map<String, dynamic>;
      (json['installed'] as Map)['runtimeRevision'] = 'a' * 40;
      await settings.writeAsString(jsonEncode(json));
      final reopened = ModelStore(
        root: root,
        catalog: [manifest],
        freeBytes: plenty,
      );
      await reopened.ready();
      expect(reopened.installedModel, null);
      expect(reopened.enabled, false);
      expect(reopened.hasModelFiles, true);
      expect(await Directory(store.installedPath!).exists(), true);
      store.dispose();
      reopened.dispose();
    },
  );

  test(
    'manifest refuses traversal, floating revisions and external/insecure sources',
    () {
      expect(
        () => ModelFile(
          name: '../model',
          size: 1,
          checksum: 'a' * 64,
          url: Uri.parse('https://huggingface.co'),
        ),
        throwsFormatException,
      );
      final json = manifest.toJson();
      json['revision'] = 'main';
      expect(() => ModelManifest.fromJson(json), throwsFormatException);
      final file = Map<String, dynamic>.from(
        (manifest.toJson()['files'] as List).first as Map,
      );
      file['url'] = 'http://example.com/model';
      final badSource = manifest.toJson()..['files'] = [file];
      expect(() => ModelManifest.fromJson(badSource), throwsFormatException);
    },
  );
}
