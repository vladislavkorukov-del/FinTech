import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'features.dart';

/// The local classification model: a softmax regression over hashed text,
/// amount and date features, trained by `tool/finora_ai/train.py` and shipped
/// as `assets/ai/finora_classifier.json` (int8 weights with a per-class
/// scale). Runs in well under a millisecond, fully offline.
class LinearModel {
  LinearModel._({
    required this.version,
    required this.schemaVersion,
    required this.preprocessingVersion,
    required this.buckets,
    required this.classes,
    required Int8List weights,
    required Float64List scale,
    required Float64List bias,
  }) : _w = weights,
       _scale = scale,
       _bias = bias;

  static const format = 'finora-linear-v1';

  /// Model file layouts this app reads (1 — before versions were recorded).
  static const supportedSchemas = {1, 2};

  /// The model's own version («1.1.0»), the file layout and the feature
  /// pipeline it was trained with.
  final String version;
  final int schemaVersion, preprocessingVersion;
  final int buckets;

  /// Canonical class ids («groceries», «cafe», …).
  final List<String> classes;
  final Int8List _w;
  final Float64List _scale, _bias;

  factory LinearModel.fromJson(Map<String, dynamic> json) {
    if (json['format'] != format) {
      throw FormatException('Unknown model format ${json['format']}');
    }
    // Files written before the versions were recorded are schema 1 with
    // features 1.
    final schema = (json['schema_version'] as num?)?.toInt() ?? 1;
    final preprocessing = (json['preprocessing_version'] as num?)?.toInt() ?? 1;
    if (!supportedSchemas.contains(schema)) {
      throw FormatException('Unsupported model schema $schema');
    }
    if (!Features.supported.contains(preprocessing)) {
      // Features this app cannot compute: the model would answer nonsense.
      throw FormatException('Unsupported preprocessing $preprocessing');
    }
    final classes = (json['classes'] as List).cast<String>();
    final buckets = (json['buckets'] as num).toInt();
    final raw = base64.decode(json['weights_b64'] as String);
    if (raw.length != buckets * classes.length) {
      throw const FormatException('Model weights have the wrong size');
    }
    return LinearModel._(
      version: json['version'] as String,
      schemaVersion: schema,
      preprocessingVersion: preprocessing,
      buckets: buckets,
      classes: classes,
      weights: Int8List.view(raw.buffer, raw.offsetInBytes, raw.length),
      scale: Float64List.fromList([
        for (final s in json['scale'] as List) (s as num).toDouble(),
      ]),
      bias: Float64List.fromList([
        for (final b in json['bias'] as List) (b as num).toDouble(),
      ]),
    );
  }

  factory LinearModel.parse(String source) =>
      LinearModel.fromJson(jsonDecode(source) as Map<String, dynamic>);

  /// Probabilities for every class, in [classes] order.
  List<double> probabilities(TransactionInput t) {
    final (idx, value) = Features.vector(
      t,
      buckets,
      version: preprocessingVersion,
    );
    final n = classes.length;
    final logits = List<double>.generate(n, (c) => _bias[c]);
    final acc = List<double>.filled(n, 0);
    for (final i in idx) {
      final row = i * n;
      for (var c = 0; c < n; c++) {
        acc[c] += _w[row + c];
      }
    }
    for (var c = 0; c < n; c++) {
      logits[c] += acc[c] * _scale[c] * value;
    }
    final top = logits.reduce(math.max);
    final exps = [for (final l in logits) math.exp(l - top)];
    final sum = exps.fold<double>(0, (a, b) => a + b);
    return [for (final e in exps) e / sum];
  }

  /// Parses [source] on a background isolate: the 300 KB file is decoded
  /// off the UI thread.
  static Future<LinearModel> parseInBackground(String source) =>
      Isolate.run(() => LinearModel.parse(source));

  /// Top [k] classes for many operations at once, on a background isolate
  /// (imports, bulk re-classification). A single prediction is fast enough
  /// for the UI thread (see the timing test); a batch is not.
  Future<List<List<(String, double)>>> predictMany(
    List<TransactionInput> inputs, {
    int k = 3,
  }) => Isolate.run(() => [for (final t in inputs) predict(t, k: k)]);

  /// The [k] most likely classes.
  List<(String, double)> predict(TransactionInput t, {int k = 3}) {
    final p = probabilities(t);
    final order = List<int>.generate(p.length, (i) => i)
      ..sort((a, b) => p[b].compareTo(p[a]));
    return [for (final i in order.take(k)) (classes[i], p[i])];
  }
}
