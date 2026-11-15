import '../domain/finance_engine.dart';
import '../domain/models.dart';
import 'controller.dart';
import 'widgets/common.dart';
import 'widgets/finora_orb.dart';

/// What Finora says after an operation (2.2: no emotions — her light
/// swells, a line appears; [alert] for what needs attention).
abstract final class FinoraReactions {
  /// A big expense, in minor units of the base currency.
  static const bigExpense = 1000000;
  static const bigIncome = 5000000;

  /// After an operation is saved.
  static void afterEntry(FinanceController c, FinanceEntry entry) {
    final (alert, text) = forEntry(c.data, entry, c.periodStart, c.periodEnd);
    Finora.react(alert: alert, text: text);
  }

  /// Whether it needs attention, and Finora's line for a saved [entry]
  /// (also used by tests).
  static (bool, String?) forEntry(
    FinanceData data,
    FinanceEntry entry,
    DateTime start,
    DateTime end,
  ) {
    final base = data.preferences.baseCurrency;
    String sum(int v) => money(v, entry.currency);
    final category = data.categories
        .where((x) => x.id == entry.categoryId)
        .firstOrNull;
    final name = '${category?.name ?? ''} ${entry.payee}'.toLowerCase();
    switch (entry.kind) {
      case EntryKind.income:
        final salary = name.contains('зарплат') || name.contains('аванс');
        if (entry.currency == base && entry.amountMinor >= bigIncome) {
          return (
            false,
            salary
                ? 'Зарплата пришла! +${sum(entry.amountMinor)}'
                : 'Вот это доход! +${sum(entry.amountMinor)}',
          );
        }
        return (
          false,
          salary
              ? 'Зарплата пришла! +${sum(entry.amountMinor)}'
              : 'Доход: +${sum(entry.amountMinor)}',
        );
      case EntryKind.expense:
        for (final budget in data.budgets) {
          if (budget.currency != entry.currency) continue;
          if (budget.categoryId != null &&
              budget.categoryId != entry.categoryId) {
            continue;
          }
          final spent = FinanceEngine.budgetSpent(
            budget,
            data.entries,
            start,
            end,
          );
          if (spent > budget.limitMinor &&
              !entry.date.isBefore(start) &&
              entry.date.isBefore(end)) {
            return (
              true,
              'Бюджет «${budget.name}» превышен на '
                  '${money(spent - budget.limitMinor, budget.currency)}!',
            );
          }
        }
        if (entry.currency == base && entry.amountMinor >= bigExpense) {
          return (false, 'Ого! Большая трата: ${sum(entry.amountMinor)}');
        }
        return (false, null);
      case EntryKind.transfer:
        final goal = data.goals
            .where((g) => g.id == entry.toGoalId)
            .firstOrNull;
        if (goal != null) {
          final saved = FinanceEngine.goalSaved(goal, data.entries);
          if (saved >= goal.targetMinor) {
            return (false, 'Мечта «${goal.name}» накоплена!');
          }
          final percent = goal.targetMinor == 0
              ? 0
              : (saved * 100 ~/ goal.targetMinor);
          return (false, 'Ещё шаг к мечте «${goal.name}»: $percent%');
        }
        return (false, null);
    }
  }
}
