import '../domain/finance_engine.dart';
import '../domain/models.dart';
import 'controller.dart';
import 'widgets/common.dart';
import 'widgets/finora_orb.dart';

/// Which emotion goes with what (Finora 1.27):
///
/// | Что случилось | Финора |
/// |---|---|
/// | Зарплата или крупный доход | Радость / Восторг |
/// | Другой доход | Радость |
/// | Расход от 10 000 ₽ | Удивление |
/// | Бюджет превышен этим расходом | Злость |
/// | Обычный расход или перевод | Готово |
/// | Пополнение мечты | Поддержка; мечта накоплена — Восторг |
/// | Платёж сегодня | Внимание; просрочен — Злость |
/// | Платёж подтверждён | Готово; пропущен — Спокойствие |
/// | Вызов голосом | Восторг, пока слушает — Обработка |
/// | Команда выполнена | Готово; новая мечта — Удовольствие |
/// | Команда не понята | Сомнение; ошибка — Ошибка |
/// | Нет касаний 10 секунд | Ожидание |
abstract final class FinoraReactions {
  /// A big expense, in minor units of the base currency.
  static const bigExpense = 1000000;
  static const bigIncome = 5000000;

  /// After an operation is saved.
  static void afterEntry(FinanceController c, FinanceEntry entry) {
    final (mood, text) = forEntry(c.data, entry, c.periodStart, c.periodEnd);
    Finora.react(mood, text: text);
  }

  /// The mood and line for a saved [entry] (also used by tests).
  static (FinoraMood, String?) forEntry(
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
            FinoraMood.delight,
            salary
                ? 'Зарплата пришла! +${sum(entry.amountMinor)}'
                : 'Вот это доход! +${sum(entry.amountMinor)}',
          );
        }
        return (
          FinoraMood.happy,
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
              FinoraMood.angry,
              'Бюджет «${budget.name}» превышен на '
                  '${money(spent - budget.limitMinor, budget.currency)}!',
            );
          }
        }
        if (entry.currency == base && entry.amountMinor >= bigExpense) {
          return (
            FinoraMood.surprised,
            'Ого! Большая трата: ${sum(entry.amountMinor)}',
          );
        }
        return (FinoraMood.done, null);
      case EntryKind.transfer:
        final goal = data.goals
            .where((g) => g.id == entry.toGoalId)
            .firstOrNull;
        if (goal != null) {
          final saved = FinanceEngine.goalSaved(goal, data.entries);
          if (saved >= goal.targetMinor) {
            return (FinoraMood.delight, 'Мечта «${goal.name}» накоплена!');
          }
          final percent = goal.targetMinor == 0
              ? 0
              : (saved * 100 ~/ goal.targetMinor);
          return (
            FinoraMood.support,
            'Ещё шаг к мечте «${goal.name}»: $percent%',
          );
        }
        return (FinoraMood.done, null);
    }
  }
}
