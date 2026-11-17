import '../../../domain/models.dart';
import '../../../domain/payee_summary.dart';
import '../../../domain/service_catalog.dart';
import '../../../domain/service_recognizer.dart';

/// What Finora knows about one place where money goes (or comes from),
/// computed from the person's own operations.
class MerchantProfile {
  const MerchantProfile({
    required this.key,
    required this.name,
    required this.aliases,
    required this.kind,
    required this.count,
    required this.typicalAmount,
    required this.lowAmount,
    required this.highAmount,
    required this.perMonth,
    required this.lastSeen,
    this.usualCategoryId,
    this.categoryShare = 0,
    this.lastAccountId,
  });

  /// The canonical key («store_pyaterochka», or the cleaned name).
  final String key;

  /// How to show it: the brand's name, or the spelling used most often.
  final String name;

  /// Every spelling seen («PYATEROCHKA #123», «Пятерочка»…).
  final Set<String> aliases;
  final EntryKind kind;
  final int count;

  /// Median amount and the usual range (10th–90th percentile).
  final int typicalAmount, lowAmount, highAmount;

  /// Operations per month over the time it has been seen.
  final double perMonth;
  final DateTime lastSeen;

  /// The category most of its operations were filed under, and that
  /// share (0–1).
  final String? usualCategoryId;
  final double categoryShare;

  /// The account used last time.
  final String? lastAccountId;
}

/// The merchant layer: one canonical key for the many ways a bank or a
/// person writes the same place («PYATEROCHKA #123», «X5 PYATEROCHKA»,
/// «Пятерочка» are one), profiles built from history, and suggestions while
/// typing. Known brands are recognized through the app's store and service
/// catalogs; everything else is cleaned of legal forms, store numbers and
/// punctuation.
abstract final class MerchantIntelligence {
  static final _keys = <String, String>{};
  static Object? _profilesFor;
  static Map<String, MerchantProfile> _profiles = const {};

  static final _legal = RegExp(
    r'^(ооо|оао|зао|пао|ао|ип|llc|ltd|oao|ooo|zao|pao|ip)\s+|\s+(ооо|ао|llc|ltd)$',
  );
  static final _numbers = RegExp(r'(#\s*\d+)|(\b\d{3,}\b)', unicode: true);

  /// The canonical key of [raw] (memoized).
  static String canonicalKey(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    final cached = _keys[text];
    if (cached != null) return cached;
    if (_keys.length > 4000) _keys.clear();
    final known = ServiceRecognizer.find(text) ?? ServiceCatalog.byName(text);
    final String key;
    if (known != null && !ServiceCatalog.banks.contains(known)) {
      key = known.id;
    } else {
      var k = PayeeSummary.key(text.replaceAll(_numbers, ' '));
      k = k.replaceAll(_legal, '').trim();
      key = k.isEmpty ? PayeeSummary.key(text) : k;
    }
    return _keys[text] = key;
  }

  /// The brand's own name for a recognized place, else null.
  static String? brandName(String raw) {
    final known = ServiceRecognizer.find(raw) ?? ServiceCatalog.byName(raw);
    return known == null || ServiceCatalog.banks.contains(known)
        ? null
        : known.name;
  }

  /// Profiles of every place in [data], by canonical key (cached per data
  /// snapshot).
  static Map<String, MerchantProfile> profiles(FinanceData data) {
    if (identical(_profilesFor, data.entries)) return _profiles;
    final groups = <String, List<FinanceEntry>>{};
    for (final e in data.entries) {
      if (e.kind == EntryKind.transfer || e.status != 'posted') continue;
      final key = canonicalKey(e.payee);
      if (key.isEmpty) continue;
      groups.putIfAbsent('${e.kind.name}|$key', () => []).add(e);
    }
    final out = <String, MerchantProfile>{};
    for (final g in groups.entries) {
      final list = g.value..sort((a, b) => a.date.compareTo(b.date));
      final key = g.key.substring(g.key.indexOf('|') + 1);
      final amounts = [for (final e in list) e.amountMinor]..sort();
      int at(double q) => amounts[((amounts.length - 1) * q).round()];
      final spellings = <String, int>{};
      final categories = <String, int>{};
      for (final e in list) {
        final s = e.payee.trim();
        spellings[s] = (spellings[s] ?? 0) + 1;
        if (e.categoryId != null) {
          categories[e.categoryId!] = (categories[e.categoryId!] ?? 0) + 1;
        }
      }
      final usual = categories.entries.isEmpty
          ? null
          : (categories.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first;
      final often =
          (spellings.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
      final months = (list.last.date.difference(list.first.date).inDays / 30.4)
          .clamp(1.0, double.infinity);
      final profile = MerchantProfile(
        key: key,
        name: brandName(often) ?? often,
        aliases: spellings.keys.toSet(),
        kind: list.first.kind,
        count: list.length,
        typicalAmount: at(.5),
        lowAmount: at(.1),
        highAmount: at(.9),
        perMonth: list.length / months,
        lastSeen: list.last.date,
        usualCategoryId: usual?.key,
        categoryShare: usual == null ? 0 : usual.value / list.length,
        lastAccountId: list.last.accountId,
      );
      final existing = out[g.key];
      if (existing == null || existing.count < profile.count) {
        out[g.key] = profile;
      }
    }
    _profilesFor = data.entries;
    return _profiles = out;
  }

  /// The profile of [raw] for [kind], if the place was seen before.
  static MerchantProfile? profileOf(
    FinanceData data,
    String raw, {
    EntryKind kind = EntryKind.expense,
  }) => profiles(data)['${kind.name}|${canonicalKey(raw)}'];

  /// Places matching what is typed: the start of the name or of any
  /// spelling first, then anywhere in it; frequent and recent ones first.
  /// Nothing for fewer than two letters.
  static List<MerchantProfile> suggest(
    FinanceData data,
    String typed, {
    EntryKind kind = EntryKind.expense,
    int limit = 3,
  }) {
    final q = PayeeSummary.key(typed);
    if (q.length < 2) return const [];
    final scored = <(MerchantProfile, double)>[];
    for (final p in profiles(data).values) {
      if (p.kind != kind) continue;
      final names = [p.name, ...p.aliases].map(PayeeSummary.key);
      final starts = names.any((n) => n.startsWith(q));
      final contains = starts || names.any((n) => n.contains(q));
      if (!contains) continue;
      // Exactly what is typed already: nothing to suggest.
      if (names.any((n) => n == q) && p.aliases.length == 1) continue;
      final age = DateTime.now().difference(p.lastSeen).inDays;
      final score = (starts ? 2.0 : 1.0) * (1 + p.count / 10) / (1 + age / 60);
      scored.add((p, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (p, _) in scored.take(limit)) p];
  }
}
