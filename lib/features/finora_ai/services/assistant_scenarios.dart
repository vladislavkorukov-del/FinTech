import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../../../domain/payment_plan.dart';
import '../../../domain/weekly_debt_plan.dart';
import '../../../presentation/widgets/common.dart' show money, displayDate;
import '../memory/assistant_preferences.dart';
import '../models/ai_models.dart' show PeriodUnit;
import '../responses/response_layer.dart';
import 'finora_ai_snapshot.dart';

/// Reusable steps are parameters, never cached financial answers. Every run
/// reads the supplied current ledger and uses the existing calculation layer.
abstract final class AssistantScenarios {
  static String summary(
    FinanceData data, {
    required String period,
    DateTime? now,
    AssistantReportFormat format = AssistantReportFormat.brief,
  }) {
    final clock = now ?? DateTime.now();
    final day = DateTime(clock.year, clock.month, clock.day);
    final start = period == 'week'
        ? DateTime(
            day.year,
            day.month,
            day.day - (day.weekday - data.preferences.weekStart + 7) % 7,
          )
        : DateTime(day.year, day.month, 1);
    final end = period == 'week'
        ? DateTime(start.year, start.month, start.day + 7)
        : DateTime(start.year, start.month + 1, 1);
    final currency = data.preferences.baseCurrency;
    final totals = FinanceEngine.totals(data.entries, start, end, currency);
    final report =
        '${period == 'week' ? 'Неделя' : 'Месяц'} с ${displayDate(start)}\n'
        'Доходы: ${money(totals.income, currency)}\nРасходы: ${money(totals.expense, currency)}\n'
        'Разница: ${money(totals.net, currency)}';
    final extra = format == AssistantReportFormat.detailed
        ? '\n${ResponseLayer.periodComparison(FinoraAiSnapshot.compute(data, now: clock), FinoraAiSnapshot.compute(data, now: clock).compare(period == 'week' ? PeriodUnit.week : PeriodUnit.month))}'
        : '';
    return '$report$extra\nУчтены проведённые операции в $currency; переводы не считаются доходом или расходом.';
  }

  static String upcoming(
    FinanceData data, {
    int withinDays = 28,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final until = DateTime(today.year, today.month, today.day + withinDays);
    final rules =
        data.recurring
            .where(
              (r) =>
                  r.enabled &&
                  r.kind == EntryKind.expense &&
                  !r.nextDate.isAfter(until),
            )
            .toList()
          ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    if (rules.isEmpty) {
      return 'В выбранном периоде нет настроенных обязательных платежей.';
    }
    return [
      for (final r in rules)
        '${r.name}: ${money(PaymentPlan.requiredForOccurrence(r, data.entries, r.nextDate, now: clock), r.currency)} · ${displayDate(r.nextDate)}${r.nextDate.isBefore(today) ? ' · просрочено' : ''}',
    ].join('\n');
  }

  static WeeklyDebtPlan debtPlan(
    FinanceData data,
    ScenarioStep step, {
    DateTime? now,
  }) {
    if (step.type != ScenarioStepType.debtPlan) {
      throw const FormatException('В сценарии нет расчёта долгов.');
    }
    final p = step.parameters;
    final account = data.accounts
        .where((a) => a.id == p['sourceAccountId'] && !a.archived)
        .firstOrNull;
    if (account == null) {
      throw const FormatException(
        'Счёт сценария удалён или не выбран. Измените параметры.',
      );
    }
    final budget = p['budgetMinor'];
    if (budget is! int || budget <= 0) {
      throw const FormatException(
        'Укажите бюджет погашения в параметрах сценария.',
      );
    }
    if (p['currency'] != null && p['currency'] != account.currency) {
      throw const FormatException(
        'Валюта счёта изменилась. Проверьте сценарий.',
      );
    }
    final today = now ?? DateTime.now();
    return WeeklyDebtPlanner.compute(
      data,
      WeeklyDebtPlanRequest(
        sourceAccountId: account.id,
        currency: account.currency,
        budgetMinor: budget,
        reserveMinor: p['reserveMinor'] as int? ?? 0,
        from: today,
        until: DateTime(
          today.year,
          today.month,
          today.day + (p['horizonDays'] as int? ?? 28),
        ),
        planningWeekday: p['planningWeekday'] as int? ?? 1,
      ),
    );
  }
}
