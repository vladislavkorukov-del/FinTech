// Explicit developer-only real-network probe, excluded from the normal suite.
// flutter test tool/local_llm/phase4_download_probe_test.dart --no-pub
import 'dart:convert';
import 'dart:io';

import 'package:finora/features/finora_ai/local_model/model_download.dart';
import 'package:finora/features/finora_ai/local_model/model_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class ObservedHttps implements ModelValidatorTransport {
  ObservedHttps(this.responses);
  final List<(String, int, int)> responses;
  final inner = HttpsModelTransport();
  @override
  void setValidator(String? value) => inner.setValidator(value);
  @override
  Future<ModelResponse> get(Uri url, {required int offset}) async {
    final result = await inner.get(url, offset: offset);
    responses.add((p.basename(url.path), offset, result.status));
    // Deliberately no response URL or signed query in output.
    stdout.writeln(
      'HTTP file=${p.basename(url.path)} offset=$offset status=${result.status} host=${result.host}',
    );
    return result;
  }

  @override
  void close() => inner.close();
}

void main() {
  test(
    'real pinned 0.8B full package resumes a seeded verified-prefix part',
    () async {
      final json =
          jsonDecode(await File('assets/ai/local_models.json').readAsString())
              as Map;
      final manifest = ModelManifest.fromJson(
        Map<String, dynamic>.from((json['models'] as List).first as Map),
      );
      final staging = Directory('/workspace/scratch/phase4-download-08b');
      final directory = Directory(p.join(staging.path, manifest.packageKey));
      await directory.create(recursive: true);
      final partial = File(p.join(directory.path, 'llm.mnn.weight.part'));
      final finalWeight = File(p.join(directory.path, 'llm.mnn.weight'));
      // Reset only this developer-owned fixture, so every explicit run
      // proves a real HTTP resume rather than silently passing from cache.
      if (await finalWeight.exists()) await finalWeight.delete();
      {
        final source = await File(
          '/workspace/scratch/qwen-0.8b/llm.mnn.weight',
        ).open();
        try {
          await partial.writeAsBytes(
            await source.read(1024 * 1024),
            flush: true,
          );
        } finally {
          await source.close();
        }
      }
      final responseLog = <(String, int, int)>[];
      var lastPrinted = 0;
      final loader = ModelDownloader(
        stagingRoot: staging,
        freeBytes: (path) async {
          final result = await Process.run('df', ['-PB1', path]);
          if (result.exitCode != 0) {
            throw const ModelDeliveryException('Cannot inspect host disk');
          }
          return int.parse(
            (result.stdout as String)
                .trim()
                .split('\n')
                .last
                .split(RegExp(r'\s+'))[3],
          );
        },
        transport: () => ObservedHttps(responseLog),
        onDiagnostic: (data) => stdout.writeln(jsonEncode(data)),
        onProgress: (progress) {
          if (progress.receivedBytes - lastPrinted >= 50 * 1024 * 1024 ||
              progress.phase == ModelDownloadPhase.ready) {
            lastPrinted = progress.receivedBytes;
            stdout.writeln(
              'PROGRESS phase=${progress.phase.name} bytes=${progress.receivedBytes}/${progress.totalBytes} attempt=${progress.attempt}',
            );
          }
        },
      );
      try {
        final verified = await loader.download(manifest);
        expect(await verifyModelPackage(verified, manifest), true);
        expect(manifest.downloadBytes, 479005820);
        {
          expect(
            responseLog.any(
              (r) =>
                  r.$1 == 'llm.mnn.weight' &&
                  r.$2 >= 1024 * 1024 &&
                  r.$3 == 206,
            ),
            true,
          );
        }
        stdout.writeln(
          'VERIFIED model=${manifest.id} revision=${manifest.revision} bytes=${manifest.downloadBytes} all_sha256=true',
        );
      } on ModelDownloadFailure catch (e) {
        stdout.writeln('REAL_SOURCE_FAILURE ${jsonEncode(e.diagnostics())}');
        rethrow;
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
