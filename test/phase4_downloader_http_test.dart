import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:finora/features/finora_ai/local_model/model_download.dart';
import 'package:finora/features/finora_ai/local_model/model_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const revision = '3208b55b2e3c948016c9d380a697be881a1f12f8';
const runtime = 'b0239771b07b317a258fbc384683bbd540741406';
const quick = ModelDownloadRetryPolicy(
  maxAttempts: 3,
  baseDelay: Duration(milliseconds: 5),
  maxDelay: Duration(milliseconds: 15),
  jitterFraction: 0,
);

void main() {
  late Directory root;
  late HttpServer server;
  final bytes = List<int>.generate(32768, (i) => i % 251);
  ModelManifest manifest({String rev = revision}) => ModelManifest(
    id: 'http-fixture',
    label: 'Synthetic',
    source: 'taobao-mnn/test',
    revision: rev,
    format: 'MNN-LLM',
    quantization: '4-bit',
    license: 'Apache-2.0',
    runtime: 'MNN 3.6.2',
    runtimeRevision: runtime,
    files: [
      ModelFile(
        name: 'llm.mnn.weight',
        size: bytes.length,
        checksum: sha256.convert(bytes).toString(),
        url: Uri.parse(
          'https://huggingface.co/taobao-mnn/test/resolve/$rev/llm.mnn.weight',
        ),
      ),
    ],
  );
  Future<void> start(Future<void> Function(HttpRequest) handler) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      unawaited(
        handler(request).catchError((Object error) {
          // Clients intentionally close during cancellation/invalid headers.
          if (error is! IOException) throw error;
        }),
      );
    });
  }

  ModelDownloader downloader({
    ModelDownloadRetryPolicy policy = quick,
    void Function(ModelDownloadProgress)? onProgress,
    void Function(Map<String, Object?>)? onDiagnostic,
    Future<void> Function(RandomAccessFile, List<int>)? writeChunk,
    Duration idle = const Duration(seconds: 2),
    Duration connect = const Duration(seconds: 2),
  }) => ModelDownloader(
    stagingRoot: root,
    freeBytes: (_) async => 1024 * 1024 * 1024,
    retryPolicy: policy,
    onProgress: onProgress,
    onDiagnostic: onDiagnostic,
    writeChunk: writeChunk,
    transport: () => HttpsModelTransport.forTesting(
      loopbackOrigin: Uri.parse('http://127.0.0.1:${server.port}'),
      idleTimeout: idle,
      connectTimeout: connect,
    ),
  );
  Future<void> send(
    HttpRequest request, {
    int offset = 0,
    bool range = false,
    List<int>? body,
    String? etag = '"fixture-v1"',
  }) async {
    final data = body ?? bytes;
    request.response.statusCode = range ? 206 : 200;
    request.response.contentLength = data.length - offset;
    if (etag != null) {
      request.response.headers.set(HttpHeaders.etagHeader, etag);
    }
    if (range) {
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $offset-${data.length - 1}/${data.length}',
      );
    }
    request.response.add(data.sublist(offset));
    await request.response.close();
  }

  Future<void> cut(HttpRequest request, {int saved = 4096}) async {
    request.response.statusCode = 200;
    request.response.contentLength = bytes.length;
    request.response.headers.set(HttpHeaders.etagHeader, '"fixture-v1"');
    final socket = await request.response.detachSocket(writeHeaders: true);
    socket.add(bytes.sublist(0, saved));
    await socket.flush();
    socket.destroy();
  }

  File part(ModelManifest m) =>
      File(p.join(root.path, m.packageKey, 'llm.mnn.weight.part'));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('finora-http-download-');
  });
  tearDown(() async {
    try {
      await server.close(force: true);
    } catch (_) {}
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'real body disconnect resumes actual bytes using 206, If-Range and SHA',
    () async {
      final requested = <String?>[];
      final validators = <String?>[];
      var attempts = 0;
      await start((request) async {
        requested.add(request.headers.value(HttpHeaders.rangeHeader));
        validators.add(request.headers.value(HttpHeaders.ifRangeHeader));
        if (attempts++ == 0) {
          await cut(request);
          return;
        }
        final offset = int.parse(
          request.headers
              .value(HttpHeaders.rangeHeader)!
              .substring(6)
              .split('-')
              .first,
        );
        await send(request, offset: offset, range: true);
      });
      final errors = <Map<String, Object?>>[];
      final progress = <ModelDownloadProgress>[];
      final installed = await downloader(
        onDiagnostic: errors.add,
        onProgress: progress.add,
      ).download(manifest());
      expect(await verifyModelPackage(installed, manifest()), true);
      expect(requested, [null, 'bytes=4096-']);
      expect(validators, [null, '"fixture-v1"']);
      expect(errors.first['code'], 'connectionClosed');
      expect(errors.first['savedBytes'], 4096);
      expect(progress.any((p) => p.phase == ModelDownloadPhase.retrying), true);
      expect(
        progress
            .where((p) => p.phase != ModelDownloadPhase.ready)
            .every((p) => p.fraction < 1),
        true,
      );
    },
  );

  test(
    '200 after Range safely truncates and restarts instead of appending',
    () async {
      var calls = 0;
      await start((r) async {
        if (calls++ == 0) {
          await cut(r);
          return;
        }
        expect(r.headers.value('range'), 'bytes=4096-');
        await send(r);
      });
      final installed = await downloader().download(manifest());
      expect(await verifyModelPackage(installed, manifest()), true);
      expect(calls, 2);
    },
  );

  test(
    'incorrect Content-Range rejected without corrupting existing part',
    () async {
      final m = manifest();
      await part(m).parent.create(recursive: true);
      await part(m).writeAsBytes(bytes.sublist(0, 1024));
      await start((r) async {
        r.response.statusCode = 206;
        r.response.headers.set(
          'content-range',
          'bytes 0-${bytes.length - 1}/${bytes.length}',
        );
        r.response.contentLength = bytes.length;
        r.response.add(bytes);
        await r.response.close();
      });
      await expectLater(
        downloader(policy: ModelDownloadRetryPolicy.none).download(m),
        throwsA(
          isA<ModelDownloadFailure>().having(
            (e) => e.code,
            'code',
            ModelDownloadErrorCode.invalidRange,
          ),
        ),
      );
      expect(await part(m).length(), 1024);
    },
  );

  test(
    '416 never installs an incomplete file; restart gets full verified data',
    () async {
      final m = manifest();
      await part(m).parent.create(recursive: true);
      await part(m).writeAsBytes(bytes.sublist(0, 1000));
      var calls = 0;
      await start((r) async {
        if (calls++ == 0) {
          expect(r.headers.value('range'), 'bytes=1000-');
          r.response.statusCode = 416;
          r.response.headers.set('content-range', 'bytes */${bytes.length}');
          await r.response.close();
          return;
        }
        expect(r.headers.value('range'), null);
        await send(r);
      });
      final installed = await downloader().download(m);
      expect(await verifyModelPackage(installed, m), true);
      expect(calls, 2);
    },
  );

  test(
    'a complete verified .part promotes without asking for an invalid Range',
    () async {
      final m = manifest();
      await part(m).parent.create(recursive: true);
      await part(m).writeAsBytes(bytes);
      var calls = 0;
      await start((r) async {
        calls++;
        r.response.statusCode = 416;
        await r.response.close();
      });
      final installed = await downloader().download(m);
      expect(await verifyModelPackage(installed, m), true);
      expect(calls, 0);
    },
  );

  test(
    '403 after signed CDN redirect obtains a fresh canonical redirect',
    () async {
      var resolves = 0;
      final visited = <String>[];
      final diagnostics = <Map<String, Object?>>[];
      await start((r) async {
        visited.add(r.uri.toString());
        expect(r.headers.value('authorization'), null);
        if (r.uri.path.contains('/resolve/')) {
          resolves++;
          r.response.statusCode = 302;
          r.response.headers.set('location', '/cdn?Signature=secret-$resolves');
          await r.response.close();
          return;
        }
        if (resolves == 1) {
          r.response.statusCode = 403;
          await r.response.close();
          return;
        }
        await send(r);
      });
      final installed = await downloader(
        onDiagnostic: diagnostics.add,
      ).download(manifest());
      expect(await verifyModelPackage(installed, manifest()), true);
      expect(resolves, 2);
      expect(visited.where((u) => u.contains('Signature=')).length, 2);
      final exported = jsonEncode(diagnostics);
      expect(exported, contains('forbidden'));
      expect(exported, isNot(contains('secret-')));
      expect(exported, isNot(contains('Signature=')));
    },
  );

  test('429 honors Retry-After and bounded retry succeeds', () async {
    var calls = 0;
    DateTime? limited, next;
    await start((r) async {
      if (calls++ == 0) {
        limited = DateTime.now();
        r.response.statusCode = 429;
        r.response.headers.set('retry-after', '1');
        await r.response.close();
        return;
      }
      next = DateTime.now();
      await send(r);
    });
    await downloader().download(manifest());
    expect(
      next!.difference(limited!).inMilliseconds,
      greaterThanOrEqualTo(950),
    );
    expect(calls, 2);
  });

  test('temporary 5xx retries but 401 and 404 do not loop', () async {
    var calls = 0;
    var status = 503;
    await start((r) async {
      calls++;
      if (status == 503 && calls > 1) {
        await send(r);
        return;
      }
      r.response.statusCode = status;
      await r.response.close();
    });
    await downloader().download(manifest());
    expect(calls, 2);
    for (final s in [401, 404]) {
      status = s;
      calls = 0;
      await root.delete(recursive: true);
      await root.create();
      await expectLater(
        downloader().download(manifest()),
        throwsA(
          isA<ModelDownloadFailure>().having((e) => e.status, 'status', s),
        ),
      );
      expect(calls, 1);
    }
  });

  test('persistent server failure stops after configured attempts', () async {
    var calls = 0;
    await start((r) async {
      calls++;
      r.response.statusCode = 503;
      await r.response.close();
    });
    await expectLater(
      downloader().download(manifest()),
      throwsA(
        isA<ModelDownloadFailure>().having((e) => e.attempt, 'attempt', 3),
      ),
    );
    expect(calls, 3);
  });

  test(
    'checksum mismatch deletes bad payload and does not claim ready',
    () async {
      await start((r) => send(r, body: List.filled(bytes.length, 42)));
      final m = manifest();
      await expectLater(
        downloader().download(m),
        throwsA(
          isA<ModelDownloadFailure>().having(
            (e) => e.code,
            'code',
            ModelDownloadErrorCode.checksum,
          ),
        ),
      );
      expect(await part(m).exists(), false);
      expect(
        await File(p.join(part(m).parent.path, 'llm.mnn.weight')).exists(),
        false,
      );
    },
  );

  test(
    'HTML, JSON error and compressed transfer cannot become model weights',
    () async {
      var type = 'text/html';
      var encoding = 'identity';
      await start((r) async {
        r.response.headers.set('content-type', type);
        r.response.headers.set('content-encoding', encoding);
        r.response.contentLength = bytes.length;
        r.response.add(bytes);
        await r.response.close();
      });
      for (final t in [
        'text/html',
        'application/json',
        'application/octet-stream',
      ]) {
        type = t;
        encoding = t == 'application/octet-stream' ? 'gzip' : 'identity';
        await expectLater(
          downloader().download(manifest()),
          throwsA(isA<ModelDownloadFailure>()),
        );
      }
    },
  );

  test(
    'disk write error records actual saved bytes and remains resumable',
    () async {
      await start((r) => send(r));
      var first = true;
      await expectLater(
        downloader(
          writeChunk: (file, chunk) async {
            if (first) {
              first = false;
              await file.writeFrom(chunk, 0, 100);
              throw const FileSystemException(
                'secret path',
                '/private',
                OSError('No space', 28),
              );
            }
            await file.writeFrom(chunk);
          },
        ).download(manifest()),
        throwsA(
          isA<ModelDownloadFailure>().having(
            (e) => e.code,
            'code',
            ModelDownloadErrorCode.noSpace,
          ),
        ),
      );
      expect(await part(manifest()).length(), 100);
      final meta = jsonDecode(
        await File('${part(manifest()).path}.json').readAsString(),
      );
      expect(meta['savedBytes'], 100);
    },
  );

  test(
    'cancel interrupts idle response and backoff immediately, preserving bytes',
    () async {
      final release = Completer<void>();
      var mode = 'idle';
      await start((r) async {
        if (mode == 'retry') {
          r.response.statusCode = 429;
          r.response.headers.set('retry-after', '60');
          await r.response.close();
          return;
        }
        r.response.contentLength = bytes.length;
        final socket = await r.response.detachSocket(writeHeaders: true);
        socket.add(bytes.sublist(0, 512));
        await socket.flush();
        await release.future;
        socket.destroy();
      });
      late ModelDownloader active;
      active = downloader(
        onProgress: (p) {
          if (p.receivedBytes > 0) active.cancel();
        },
      );
      final clock = Stopwatch()..start();
      await expectLater(
        active.download(manifest()),
        throwsA(isA<ModelDownloadCancelled>()),
      );
      expect(clock.elapsedMilliseconds, lessThan(1000));
      expect(await part(manifest()).length(), 512);
      release.complete();
      mode = 'retry';
      await root.delete(recursive: true);
      await root.create();
      active = downloader(
        onProgress: (p) {
          if (p.phase == ModelDownloadPhase.retrying) active.cancel();
        },
      );
      clock.reset();
      await expectLater(
        active.download(manifest()),
        throwsA(isA<ModelDownloadCancelled>()),
      );
      expect(clock.elapsedMilliseconds, lessThan(1000));
    },
  );

  test(
    'idle timeout differs from header/connect timeout and retains part',
    () async {
      final release = Completer<void>();
      var mode = 'body';
      await start((r) async {
        if (mode == 'body') {
          r.response.contentLength = bytes.length;
          final socket = await r.response.detachSocket(writeHeaders: true);
          socket.add(bytes.sublist(0, 123));
          await socket.flush();
          await release.future;
          socket.destroy();
          return;
        }
        await release.future;
        await r.response.close();
      });
      await expectLater(
        downloader(
          policy: ModelDownloadRetryPolicy.none,
          idle: const Duration(milliseconds: 40),
        ).download(manifest()),
        throwsA(
          isA<ModelDownloadFailure>().having(
            (e) => e.code,
            'code',
            ModelDownloadErrorCode.idleTimeout,
          ),
        ),
      );
      expect(await part(manifest()).length(), 123);
      mode = 'headers';
      await root.delete(recursive: true);
      await root.create();
      await expectLater(
        downloader(
          policy: ModelDownloadRetryPolicy.none,
          connect: const Duration(milliseconds: 40),
        ).download(manifest()),
        throwsA(
          isA<ModelDownloadFailure>().having(
            (e) => e.code,
            'code',
            ModelDownloadErrorCode.connectTimeout,
          ),
        ),
      );
      release.complete();
    },
  );

  test(
    'new downloader after interruption resumes sidecar state without reset',
    () async {
      var calls = 0;
      await start((r) async {
        if (calls++ == 0) {
          await cut(r, saved: 2345);
          return;
        }
        expect(r.headers.value('range'), 'bytes=2345-');
        expect(r.headers.value('if-range'), '"fixture-v1"');
        await send(r, offset: 2345, range: true);
      });
      final m = manifest();
      await expectLater(
        downloader(policy: ModelDownloadRetryPolicy.none).download(m),
        throwsA(isA<ModelDownloadFailure>()),
      );
      final meta = jsonDecode(
        await File('${part(m).path}.json').readAsString(),
      );
      expect(meta['revision'], revision);
      expect(meta['savedBytes'], 2345);
      final installed = await downloader().download(m);
      expect(await verifyModelPackage(installed, m), true);
    },
  );

  test(
    'double start cannot create concurrent writers for the same package',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      await start((r) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        await send(r);
      });
      final a = downloader();
      final first = a.download(manifest());
      await entered.future;
      await expectLater(
        downloader().download(manifest()),
        throwsA(
          isA<ModelDownloadFailure>().having(
            (e) => e.code,
            'code',
            ModelDownloadErrorCode.busy,
          ),
        ),
      );
      release.complete();
      await first;
    },
  );

  test('changed revision starts without mixing prior partial bytes', () async {
    final old = manifest();
    await part(old).parent.create(recursive: true);
    await part(old).writeAsBytes(bytes.sublist(0, 1000));
    final updated = manifest(rev: '1111111111111111111111111111111111111111');
    await start((r) async {
      expect(r.uri.path, contains(updated.revision));
      expect(r.headers.value('range'), null);
      await send(r);
    });
    final installed = await downloader().download(updated);
    expect(await verifyModelPackage(installed, updated), true);
    expect(await part(old).parent.exists(), false);
  });

  test('error categories are distinct and details never expose signed URLs', () {
    expect(
      classifyDownloadError(
        const SocketException('Failed host lookup: hidden'),
      ).code,
      ModelDownloadErrorCode.dns,
    );
    expect(
      classifyDownloadError(
        const SocketException(
          'Network unreachable',
          osError: OSError('network', 101),
        ),
      ).code,
      ModelDownloadErrorCode.networkUnavailable,
    );
    expect(
      classifyDownloadError(const HandshakeException('certificate')).code,
      ModelDownloadErrorCode.tls,
    );
    expect(
      sanitizeDownloadDetails(
        'HttpException uri=https://cdn.example/x?Signature=secret&token=abc Authorization: Bearer private',
      ),
      isNot(contains('secret')),
    );
    expect(
      sanitizeDownloadDetails('Authorization: Bearer PRIVATE_TOKEN'),
      isNot(contains('PRIVATE_TOKEN')),
    );
    expect(
      sanitizeDownloadDetails('HTTPS://cdn.test/x?Signature=UPPER_SECRET'),
      isNot(contains('UPPER_SECRET')),
    );
  });
}
