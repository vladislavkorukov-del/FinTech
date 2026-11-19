import 'dart:convert';
import 'dart:math' as math;

/// Features of an operation for the local classifier. MUST stay identical to
/// `tool/finora_ai/features.py` (the training side); a parity test checks
/// both produce the same predictions on shared fixtures.
class TransactionInput {
  const TransactionInput({
    required this.merchant,
    this.description = '',
    required this.amountMinor,
    required this.kind,
    this.accountType = '',
    required this.date,
  });
  final String merchant, description, accountType;
  final int amountMinor;

  /// 'expense' or 'income'.
  final String kind;
  final DateTime date;
}

abstract final class Features {
  /// Version of the feature pipeline (same as `PREPROCESSING_VERSION` in
  /// features.py). 1 — merchant 3-grams, words, kind, amount bucket,
  /// weekday, month, account type; 2 — plus amount bucket × kind. A model
  /// is used with the version it was trained with.
  static const preprocessingVersion = 2;

  /// The versions this app can compute.
  static const supported = {1, 2};

  /// Lower case, ё → е, anything but Latin/Cyrillic letters and digits
  /// becomes a space, spaces collapsed.
  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim();

  /// 32-bit FNV-1a over UTF-8.
  static int fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode(s)) {
      h ^= b;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// The feature strings of [t] (before hashing).
  static List<String> tokens(
    TransactionInput t, {
    int version = preprocessingVersion,
  }) {
    final merchant = normalize(t.merchant);
    final text = normalize('${t.merchant} ${t.description}');
    final out = <String>[];
    // Character 3-grams of the merchant, padded, ignoring digits-only runs.
    final m = ' ${merchant.replaceAll(RegExp(r'\d+'), '0')} ';
    for (var i = 0; i + 3 <= m.length; i++) {
      out.add('c3:${m.substring(i, i + 3)}');
    }
    for (final w in text.split(' ')) {
      if (w.length >= 2 && !RegExp(r'^\d+$').hasMatch(w)) out.add('w:$w');
    }
    out
      ..add('k:${t.kind}')
      ..add('a:${amountBucket(t.amountMinor)}')
      ..add('d:${t.date.weekday}')
      ..add('m:${t.date.month}')
      ..add('t:${t.accountType}');
    if (version >= 2) out.add('ak:${t.kind}:${amountBucket(t.amountMinor)}');
    return out;
  }

  /// ⌊log2⌋ of whole rubles, 0–20 (integer arithmetic, so both sides agree
  /// exactly).
  static int amountBucket(int minor) {
    final rub = minor.abs() ~/ 100;
    if (rub < 1) return 0;
    return (rub.bitLength - 1).clamp(0, 20);
  }

  /// Hashed, de-duplicated feature indices with equal weight 1/√n.
  static (List<int>, double) vector(
    TransactionInput t,
    int buckets, {
    int version = preprocessingVersion,
  }) {
    final idx = {
      for (final s in tokens(t, version: version)) fnv1a(s) % buckets,
    }.toList();
    return (idx, idx.isEmpty ? 0 : 1 / math.sqrt(idx.length));
  }
}
