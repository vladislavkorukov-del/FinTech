import 'assistant_preferences.dart';

/// Finora's personal memory: what the person has taught her, kept small and
/// structured so engines can calculate with it. It holds only the person's
/// own signals — confirmations, corrections, rejected and confirmed
/// suggestions. Typical amounts, days and ranges are not stored: they are
/// recomputed from the operations themselves, so the memory never drifts
/// from the data.
class PersonalMemory {
  PersonalMemory({
    Map<String, Map<String, MerchantVote>>? merchants,
    List<Correction>? corrections,
    Set<String>? rejected,
    Set<String>? confirmedSubscriptions,
    Set<String>? confirmedRecurring,
    Map<String, DateTime>? snoozed,
    Set<String>? excludedMonths,
    AssistantPreferences? preferences,
    List<SavedAssistantScenario>? scenarios,
  }) : preferences = preferences ?? AssistantPreferences(),
       scenarios = scenarios ?? [],
       snoozed = snoozed ?? {},
       excludedMonths = excludedMonths ?? {},
       merchants = merchants ?? {},
       corrections = corrections ?? [],
       rejected = rejected ?? {},
       confirmedSubscriptions = confirmedSubscriptions ?? {},
       confirmedRecurring = confirmedRecurring ?? {};

  /// 4: explicitly confirmed assistant preferences and typed scenarios.
  static const version = 4;

  AssistantPreferences preferences;
  final List<SavedAssistantScenario> scenarios;
  static const _maxCorrections = 300;

  /// merchant key → category id → votes.
  final Map<String, Map<String, MerchantVote>> merchants;

  /// The most recent corrections (a category changed by the person).
  final List<Correction> corrections;

  /// Suggestions the person turned down: `subscription:merchant`,
  /// `recurring:merchant`, `budget:category` (optionally `@evidence`).
  final Set<String> rejected;
  final Set<String> confirmedSubscriptions, confirmedRecurring;

  /// Insights the person put aside: dedup key → shown again after this
  /// moment (a cooldown, so the same fact is not repeated every day).
  final Map<String, DateTime> snoozed;

  /// Unusual months the person asked not to count in forecasts (`yyyy-m`).
  final Set<String> excludedMonths;

  /// Hides insights with [dedupKey] for [days].
  void snooze(String dedupKey, {int days = 7, DateTime? now}) =>
      snoozed[dedupKey] = (now ?? DateTime.now()).add(Duration(days: days));

  bool isSnoozed(String dedupKey, DateTime now) {
    final until = snoozed[dedupKey];
    if (until == null) return false;
    if (now.isAfter(until)) {
      snoozed.remove(dedupKey);
      return false;
    }
    return true;
  }

  /// The person saved [merchant] under [categoryId]. A correction (they
  /// changed it from [previous]) weighs three times a plain save.
  void observe(
    String merchant,
    String categoryId, {
    String? previous,
    DateTime? at,
  }) {
    if (merchant.isEmpty) return;
    final when = at ?? DateTime.now();
    final votes = merchants.putIfAbsent(merchant, () => {});
    final correction = previous != null && previous != categoryId;
    final v = votes[categoryId] ?? MerchantVote(0, when);
    votes[categoryId] = MerchantVote(v.weight + (correction ? 3 : 1), when);
    if (correction) {
      corrections.add(Correction(merchant, previous, categoryId, when));
      if (corrections.length > _maxCorrections) {
        corrections.removeRange(0, corrections.length - _maxCorrections);
      }
      // The old choice loses trust.
      final old = votes[previous];
      if (old != null) {
        votes[previous] = MerchantVote(
          (old.weight - 2).clamp(0, 1 << 30),
          old.at,
        );
      }
    }
  }

  /// The person's choice for [merchant]: the category with most weight,
  /// with a confidence that grows with agreement and with use.
  ({String categoryId, double confidence, int weight})? categoryFor(
    String merchant,
  ) {
    final votes = merchants[merchant];
    if (votes == null || votes.isEmpty) return null;
    final ranked = votes.entries.where((e) => e.value.weight > 0).toList()
      ..sort((a, b) {
        final w = b.value.weight.compareTo(a.value.weight);
        return w != 0 ? w : b.value.at.compareTo(a.value.at);
      });
    if (ranked.isEmpty) return null;
    final total = ranked.fold<int>(0, (a, e) => a + e.value.weight);
    final share = ranked.first.value.weight / total;
    // One save: .72; agreement and repetition lift it towards .99.
    final strength = 1 - 1 / (1 + ranked.first.value.weight);
    final confidence = (.55 + .44 * strength) * share;
    return (
      categoryId: ranked.first.key,
      confidence: confidence,
      weight: ranked.first.value.weight,
    );
  }

  bool isRejected(String key) =>
      rejected.any((r) => r == key || r.startsWith('$key@'));

  /// Rejects [key]; with [evidence] (e.g. the number of payments seen) the
  /// suggestion may come back once there is clearly more evidence.
  void reject(String key, {int? evidence}) {
    unreject(key);
    rejected.add(evidence == null ? key : '$key@$evidence');
  }

  void unreject(String key) =>
      rejected.removeWhere((r) => r == key || r.startsWith('$key@'));

  /// Still rejected given [evidence] now: a rejection made with less than
  /// [evidence] − [margin] stops holding — there are new grounds.
  bool stillRejected(String key, int evidence, {int margin = 3}) {
    for (final r in rejected) {
      if (r == key) return true;
      if (r.startsWith('$key@')) {
        final then = int.tryParse(r.substring(key.length + 1)) ?? 0;
        return evidence < then + margin;
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'preferences': preferences.toJson(),
    'scenarios': [for (final s in scenarios) s.toJson()],
    'merchants': {
      for (final m in merchants.entries)
        m.key: {for (final c in m.value.entries) c.key: c.value.toJson()},
    },
    'corrections': [for (final c in corrections) c.toJson()],
    'rejected': rejected.toList(),
    'subscriptions': confirmedSubscriptions.toList(),
    'recurring': confirmedRecurring.toList(),
    'excludedMonths': excludedMonths.toList(),
    'snoozed': {
      for (final e in snoozed.entries) e.key: e.value.toIso8601String(),
    },
  };

  factory PersonalMemory.fromJson(Map<String, dynamic> json) {
    final schema = json['version'] ?? 1;
    if (schema is! int || schema < 1 || schema > version) {
      throw const FormatException(
        'Версия персональной памяти не поддерживается',
      );
    }
    final rawPreferences = json['preferences'];
    if (rawPreferences != null && rawPreferences is! Map ||
        json['scenarios'] != null && json['scenarios'] is! List) {
      throw const FormatException('Некорректная память предпочтений');
    }
    return PersonalMemory(
      preferences: rawPreferences == null
          ? null
          : AssistantPreferences.fromJson(
              Map<String, dynamic>.from(rawPreferences as Map),
            ),
      scenarios: [
        for (final s in json['scenarios'] as List? ?? [])
          if (s is Map)
            SavedAssistantScenario.fromJson(Map<String, dynamic>.from(s))
          else
            throw const FormatException('Некорректный сохранённый сценарий'),
      ],
      merchants: {
        for (final m in (json['merchants'] as Map? ?? {}).entries)
          m.key as String: {
            for (final c in (m.value as Map).entries)
              c.key as String: MerchantVote.fromJson(c.value as Map),
          },
      },
      corrections: [
        for (final c in json['corrections'] as List? ?? const [])
          Correction.fromJson(c as Map),
      ],
      rejected: {...(json['rejected'] as List? ?? const []).cast<String>()},
      confirmedSubscriptions: {
        ...(json['subscriptions'] as List? ?? const []).cast<String>(),
      },
      confirmedRecurring: {
        ...(json['recurring'] as List? ?? const []).cast<String>(),
      },
      excludedMonths: {
        ...(json['excludedMonths'] as List? ?? const []).cast<String>(),
      },
      snoozed: {
        for (final e in (json['snoozed'] as Map? ?? const {}).entries)
          e.key as String: ?DateTime.tryParse('${e.value}'),
      },
    );
  }
}

class MerchantVote {
  const MerchantVote(this.weight, this.at);
  final int weight;
  final DateTime at;

  Map<String, dynamic> toJson() => {'w': weight, 'at': at.toIso8601String()};
  factory MerchantVote.fromJson(Map json) => MerchantVote(
    (json['w'] as num).toInt(),
    DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime(2000),
  );
}

class Correction {
  const Correction(this.merchant, this.from, this.to, this.at);
  final String merchant, to;
  final String? from;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'm': merchant,
    'from': from,
    'to': to,
    'at': at.toIso8601String(),
  };
  factory Correction.fromJson(Map json) => Correction(
    json['m'] as String,
    json['from'] as String?,
    json['to'] as String,
    DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime(2000),
  );
}
