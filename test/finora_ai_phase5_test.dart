import 'dart:convert';
import 'dart:io';

import 'package:finora/features/finora_ai/inference/features.dart';
import 'package:finora/features/finora_ai/inference/linear_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finora AI, phase 5: the local classifier's feature and file versions,
/// loading and batch inference off the UI thread, and the shipped model's
/// recorded quality.
void main() {
  final source = File('assets/ai/finora_classifier.json').readAsStringSync();
  final json = jsonDecode(source) as Map<String, dynamic>;
  final t = TransactionInput(
    merchant: 'Пятёрочка',
    amountMinor: 45000,
    kind: 'expense',
    accountType: 'card',
    date: DateTime(2026, 5, 13),
  );

  test('features 2 add amount × kind; features 1 stay as they were', () {
    final v1 = Features.tokens(t, version: 1);
    final v2 = Features.tokens(t, version: 2);
    expect(v1.where((s) => s.startsWith('ak:')), isEmpty);
    expect(v2, contains('ak:expense:${Features.amountBucket(45000)}'));
    expect(v2.toSet().difference(v1.toSet()), {'ak:expense:8'});
  });

  test('the Dart and Python feature versions are the same', () {
    final py = File('tool/finora_ai/features.py').readAsStringSync();
    final m = RegExp(
      r'^PREPROCESSING_VERSION = (\d+)',
      multiLine: true,
    ).firstMatch(py)!;
    expect(int.parse(m.group(1)!), Features.preprocessingVersion);
    expect(Features.supported, contains(Features.preprocessingVersion));
  });

  test('the shipped model records its versions and quality', () {
    final model = LinearModel.parse(source);
    expect(model.schemaVersion, 2);
    expect(model.preprocessingVersion, Features.preprocessingVersion);
    expect(model.version, '1.1.0');
    final metrics =
        jsonDecode(File('tool/finora_ai/metrics.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(metrics['version'], model.version);
    expect(metrics['preprocessing_version'], model.preprocessingVersion);
    final cross = metrics['cross_split'] as Map<String, dynamic>;
    expect(cross['splits'], 6);
    // Held-out merchants, mean of six splits (synthetic data).
    expect(cross['accuracy_mean'], greaterThan(.6));
    expect(cross['top3_accuracy_mean'], greaterThan(.7));
  });

  test('an older file without versions is read with features 1', () {
    final old = Map<String, dynamic>.from(json)
      ..remove('schema_version')
      ..remove('preprocessing_version');
    final model = LinearModel.fromJson(old);
    expect(model.schemaVersion, 1);
    expect(model.preprocessingVersion, 1);
    // It still answers (with the features it was trained with).
    expect(model.predict(t), hasLength(3));
  });

  test('unknown file layouts and feature versions are refused', () {
    expect(
      () => LinearModel.fromJson({...json, 'schema_version': 99}),
      throwsFormatException,
    );
    expect(
      () => LinearModel.fromJson({...json, 'preprocessing_version': 99}),
      throwsFormatException,
    );
    expect(
      () => LinearModel.fromJson({...json, 'format': 'other'}),
      throwsFormatException,
    );
  });

  test('loading and batch inference run on a background isolate', () async {
    final model = await LinearModel.parseInBackground(source);
    expect(model.version, '1.1.0');
    final inputs = [
      t,
      TransactionInput(
        merchant: 'Яндекс Go',
        amountMinor: 38900,
        kind: 'expense',
        date: DateTime(2026, 5, 13),
      ),
      TransactionInput(
        merchant: 'Зарплата',
        amountMinor: 9000000,
        kind: 'income',
        date: DateTime(2026, 5, 13),
      ),
    ];
    final batch = await model.predictMany(inputs, k: 1);
    for (var i = 0; i < inputs.length; i++) {
      expect(batch[i].single.$1, model.predict(inputs[i], k: 1).single.$1);
    }
  });

  test('one prediction is quick enough for the UI thread (host)', () {
    final model = LinearModel.parse(source);
    for (var i = 0; i < 50; i++) {
      model.predict(t);
    }
    final watch = Stopwatch()..start();
    const n = 500;
    for (var i = 0; i < n; i++) {
      model.predict(t);
    }
    final perCall = watch.elapsedMicroseconds / n;
    // A generous bound on the build machine; the phone is slower, but a
    // batch goes to [LinearModel.predictMany] anyway.
    expect(perCall, lessThan(2000));
  });
}
