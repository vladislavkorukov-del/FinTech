import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../memory/personal_memory.dart';
import '../models/ai_models.dart';
import '../services/ai_context.dart';

/// Suggestions built only from the person's numbers: budgets for categories
/// that have none (the median of the last full periods, rounded up to
/// 500 ₽), and how much the goals need a month against the free money.
abstract final class RecommendationEngine {
  static List<BudgetSuggestion> budgets(
    AiContext ctx, {
    PersonalMemory? memory,
  }) {
    final periods = ctx.fullPeriodsWithData.take(3).toList();
    if (periods.length < 2) return const [];
    final covered = {for (final b in ctx.data.budgets) b.categoryId};
    final values = <String, List<int>>{};
    for (final back in periods) {
      final (s, e) = ctx.period(back);
      final totals = ctx.byCategory(ctx.expensesIn(s, e));
      for (final c in ctx.data.categories.where(
        (c) => c.kind == EntryKind.expense && !c.archived,
      )) {
        values.putIfAbsent(c.id, () => []).add(totals[c.id] ?? 0);
      }
    }
    final out = <BudgetSuggestion>[];
    for (final v in values.entries) {
      if (covered.contains(v.key)) continue;
      if (memory?.isRejected('budget:${v.key}') ?? false) continue;
      final used = v.value.where((x) => x > 0).length;
      if (used < 2) continue;
      final mid = median(v.value);
      if (mid < 200000) continue; // below 2 000 ₽ a month: not worth it
      final limit = ((mid / 50000).ceil()) * 50000;
      out.add(BudgetSuggestion(v.key, limit, periods.length));
    }
    out.sort((a, b) => b.limit.compareTo(a.limit));
    return out.take(5).toList();
  }

  /// Monthly saving each open goal needs to arrive in time (the app's own
  /// [FinanceEngine.savingsPace]).
  static List<(Goal, int)> goalNeeds(AiContext ctx) {
    final out = <(Goal, int)>[];
    for (final g in ctx.data.goals) {
      if (g.currency != ctx.currency || g.deadline == null) continue;
      final saved = FinanceEngine.goalSaved(g, ctx.data.entries);
      final pace = FinanceEngine.savingsPace(g, saved, now: ctx.now);
      if (pace == null || pace.left <= 0) continue;
      out.add((g, pace.month));
    }
    return out;
  }
}
