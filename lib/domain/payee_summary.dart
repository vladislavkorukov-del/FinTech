import 'models.dart';

/// One bar of the payee chart: `[start, end)` and the amount per currency.
class PayeeBucket {
  const PayeeBucket(this.start, this.end, this.minor);
  final DateTime start, end;
  final int minor;
}

/// Spending (or income) with one payee over a period, per currency.
/// Only posted operations of the same kind count; currencies are never added
/// together or converted. Amounts are integer minor units.
class PayeeSummary {
  const PayeeSummary({
    required this.payee,
    required this.kind,
    required this.start,
    required this.end,
    required this.entries,
    required this.totals,
    required this.counts,
  });

  final String payee;
  final EntryKind kind;
  final DateTime start, end;

  /// Matching operations, newest first.
  final List<FinanceEntry> entries;
  final Map<String, int> totals;
  final Map<String, int> counts;

  int get count => entries.length;

  /// Average per operation in [currency], rounded half up to a minor unit.
  int average(String currency) {
    final n = counts[currency] ?? 0;
    if (n == 0) return 0;
    final total = totals[currency] ?? 0;
    return (total + n ~/ 2) ~/ n;
  }

  /// Bars for [currency]: days for periods up to 31 days, otherwise
  /// calendar months (at most the last 24).
  List<PayeeBucket> buckets(String currency) {
    final days = end.difference(start).inDays;
    final result = <PayeeBucket>[];
    if (days <= 31) {
      for (
        var d = DateTime(start.year, start.month, start.day);
        d.isBefore(end);
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        result.add(PayeeBucket(d, DateTime(d.year, d.month, d.day + 1), 0));
      }
    } else {
      for (
        var m = DateTime(start.year, start.month);
        m.isBefore(end);
        m = DateTime(m.year, m.month + 1)
      ) {
        result.add(PayeeBucket(m, DateTime(m.year, m.month + 1), 0));
      }
    }
    final trimmed = result.length > 24
        ? result.sublist(result.length - 24)
        : result;
    return [
      for (final b in trimmed)
        PayeeBucket(
          b.start,
          b.end,
          entries
              .where(
                (e) =>
                    e.currency == currency &&
                    !e.date.isBefore(b.start) &&
                    e.date.isBefore(b.end),
              )
              .fold(0, (sum, e) => sum + e.amountMinor),
        ),
    ];
  }

  /// Payee key: case, `ё`, punctuation and repeated spaces do not matter
  /// («WHOOSH», «Whoosh », «Whoosh.» are one payee).
  static String key(String payee) => payee
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  /// Summary for [payee] and [kind] in `[start, end)`.
  static PayeeSummary compute({
    required List<FinanceEntry> entries,
    required String payee,
    required EntryKind kind,
    required DateTime start,
    required DateTime end,
  }) {
    final wanted = key(payee);
    final matching =
        entries
            .where(
              (e) =>
                  e.status == 'posted' &&
                  e.kind == kind &&
                  wanted.isNotEmpty &&
                  key(e.payee) == wanted &&
                  !e.date.isBefore(start) &&
                  e.date.isBefore(end),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final totals = <String, int>{};
    final counts = <String, int>{};
    for (final e in matching) {
      totals[e.currency] = (totals[e.currency] ?? 0) + e.amountMinor;
      counts[e.currency] = (counts[e.currency] ?? 0) + 1;
    }
    return PayeeSummary(
      payee: payee.trim(),
      kind: kind,
      start: start,
      end: end,
      entries: List.unmodifiable(matching),
      totals: Map.unmodifiable(totals),
      counts: Map.unmodifiable(counts),
    );
  }

  /// First operation date with this payee (for «всё время»), or null.
  static DateTime? firstDate(
    List<FinanceEntry> entries,
    String payee,
    EntryKind kind,
  ) {
    final wanted = key(payee);
    DateTime? first;
    for (final e in entries) {
      if (e.status != 'posted' || e.kind != kind || key(e.payee) != wanted) {
        continue;
      }
      if (first == null || e.date.isBefore(first)) first = e.date;
    }
    return first;
  }
}
