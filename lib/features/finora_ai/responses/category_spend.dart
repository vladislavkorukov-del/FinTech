import '../../../domain/models.dart';
import '../../../presentation/widgets/common.dart' show money;
import '../conversation/conversation_context.dart';
import '../models/ai_models.dart';

/// «Сколько я потратил на продукты (в прошлом месяце)?»: the sum is counted
/// from the operations (posted expenses in the base currency), and set
/// against the same stretch of the period before.
abstract final class CategorySpend {
  static String answer(
    FinanceData data, {
    required String? categoryId,
    PeriodUnit? period,
    bool previous = false,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final prefs = data.preferences;
    final currency = prefs.baseCurrency;
    var (start, end, label) = periodRange(
      period,
      clock,
      prefs.monthStart,
      prefs.weekStart,
    );
    // So far within this period; the whole of the previous one.
    var until = clock.isBefore(end) ? clock : end;
    if (previous) {
      final length = end.difference(start);
      final prevStart = switch (period) {
        PeriodUnit.week || PeriodUnit.day => start.subtract(length),
        PeriodUnit.quarter => DateTime(start.year, start.month - 3, start.day),
        PeriodUnit.year => DateTime(start.year - 1, start.month, start.day),
        _ => DateTime(start.year, start.month - 1, start.day),
      };
      end = start;
      start = prevStart;
      until = end;
      label = switch (period) {
        PeriodUnit.week => 'на прошлой неделе',
        PeriodUnit.day => 'вчера',
        PeriodUnit.quarter => 'в прошлом квартале',
        PeriodUnit.year => 'в прошлом году',
        _ => 'в прошлом месяце',
      };
    }
    final category = data.categories
        .where((c) => c.id == categoryId)
        .firstOrNull;
    bool counts(FinanceEntry e) =>
        e.kind == EntryKind.expense &&
        e.status == 'posted' &&
        e.currency == currency &&
        (category == null || e.categoryId == category.id);
    var sum = 0, count = 0;
    for (final e in data.entries) {
      if (!counts(e) || e.date.isBefore(start) || !e.date.isBefore(until)) {
        continue;
      }
      sum += e.amountMinor;
      count++;
    }
    final what = category == null ? 'Расходы' : 'На «${category.name}»';
    if (count == 0) {
      return '$what $label — ничего не потрачено.';
    }
    final text = StringBuffer(
      '$what $label — ${money(sum, currency)} '
      '($count ${_ops(count)}).',
    );
    // The same stretch of the period before, for a sense of pace.
    if (!previous) {
      final length = until.difference(start);
      final prevStart = switch (period) {
        PeriodUnit.week ||
        PeriodUnit.day => start.subtract(end.difference(start)),
        PeriodUnit.quarter => DateTime(start.year, start.month - 3, start.day),
        PeriodUnit.year => DateTime(start.year - 1, start.month, start.day),
        _ => DateTime(start.year, start.month - 1, start.day),
      };
      final prevUntil = prevStart.add(length);
      var before = 0;
      for (final e in data.entries) {
        if (!counts(e) ||
            e.date.isBefore(prevStart) ||
            !e.date.isBefore(prevUntil)) {
          continue;
        }
        before += e.amountMinor;
      }
      if (before > 0) {
        final diff = sum - before;
        text.write(
          ' За то же время прошлого периода — ${money(before, currency)}'
          '${diff == 0
              ? '.'
              : diff > 0
              ? ', сейчас больше на ${money(diff, currency)}.'
              : ', сейчас меньше на ${money(-diff, currency)}.'}',
        );
      }
    }
    return text.toString();
  }

  static String _ops(int n) {
    final t = n % 100;
    if (t >= 11 && t <= 14) return 'операций';
    return switch (n % 10) {
      1 => 'операция',
      2 || 3 || 4 => 'операции',
      _ => 'операций',
    };
  }
}
