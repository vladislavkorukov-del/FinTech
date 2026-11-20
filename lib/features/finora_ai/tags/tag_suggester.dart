import '../../../domain/models.dart';
import '../services/ai_context.dart';

/// AI tags (Phase 7): Finora suggests tags for an operation from facts —
/// a subscription, a big expense for its category, a regular place, the
/// weekend, a trip, a refund. They are only offered: the person adds a tag
/// with a tap, and the category is never changed.
abstract final class TagSuggester {
  static const max = 3;

  static List<String> suggest(
    FinanceData data, {
    required EntryKind kind,
    required int amountMinor,
    required String payee,
    required DateTime date,
    String? categoryId,
    List<String> existing = const [],
  }) {
    if (kind == EntryKind.transfer) return const [];
    final have = {for (final t in existing) t.trim().toLowerCase()};
    final out = <String>[];
    void add(String tag) {
      if (!have.contains(tag) && !out.contains(tag)) out.add(tag);
    }

    final key = AiContext.merchantKey(payee);
    final category = data.categories
        .where((c) => c.id == categoryId)
        .firstOrNull;
    final name = (category?.name ?? '').toLowerCase();

    if (kind == EntryKind.expense) {
      // A subscription the person already keeps.
      if (key.isNotEmpty &&
          data.recurring.any(
            (r) =>
                r.paymentType == 'subscription' &&
                AiContext.merchantKey(r.name) == key,
          )) {
        add('подписка');
      }
      // Big for its category: three times the usual (from 5 operations).
      if (categoryId != null && amountMinor > 0) {
        final sums =
            data.entries
                .where(
                  (e) =>
                      e.kind == EntryKind.expense &&
                      e.categoryId == categoryId &&
                      e.status == 'posted',
                )
                .map((e) => e.amountMinor)
                .toList()
              ..sort();
        if (sums.length >= 5 && amountMinor >= sums[sums.length ~/ 2] * 3) {
          add('крупная');
        }
      }
      if (RegExp(
        r'путешеств|отпуск|отдых|отел|гостиниц|авиа|билет',
      ).hasMatch(name)) {
        add('поездка');
      }
      if (date.weekday >= DateTime.saturday) add('выходные');
    }
    // A regular place: seen in three different months.
    if (key.isNotEmpty) {
      final months = <int>{
        for (final e in data.entries)
          if (e.kind == kind && AiContext.merchantKey(e.payee) == key)
            e.date.year * 12 + e.date.month,
      };
      if (months.length >= 3) add('регулярно');
    }
    // Money back from a place the person paid.
    if (kind == EntryKind.income &&
        key.isNotEmpty &&
        data.entries.any(
          (e) =>
              e.kind == EntryKind.expense &&
              AiContext.merchantKey(e.payee) == key,
        )) {
      add('возврат');
    }
    return out.take(max).toList();
  }
}
