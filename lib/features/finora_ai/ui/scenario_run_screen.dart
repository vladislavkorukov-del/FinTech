import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/models.dart';
import '../../../presentation/controller.dart';
import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/screens/transactions.dart';
import '../../../presentation/widgets/common.dart' show money;
import '../../../services/user_error.dart';
import '../local_model/assistant_diagnostics.dart';
import '../memory/assistant_preferences.dart';
import '../services/assistant_scenarios.dart';
import '../services/finora_ai.dart';
import 'debt_planning_screen.dart';

class ScenarioRunScreen extends StatelessWidget {
  const ScenarioRunScreen({super.key, required this.scenario});
  final SavedAssistantScenario scenario;

  @override
  Widget build(BuildContext context) {
    final data = FinanceScope.of(context).data;
    return Scaffold(
      appBar: AppBar(title: Text(scenario.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Расчёт по текущим данным. Ничего не сохраняется автоматически.',
          ),
          for (final step in scenario.steps)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _step(context, data, step),
              ),
            ),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, FinanceData data, ScenarioStep step) {
    try {
      switch (step.type) {
        case ScenarioStepType.summary:
          return Text(
            AssistantScenarios.summary(
              data,
              period: step.parameters['period'] as String? ?? 'month',
              format: FinoraAi.instance.memory.preferences.reportFormat,
            ),
          );
        case ScenarioStepType.upcomingPayments:
          return Text(
            AssistantScenarios.upcoming(
              data,
              withinDays: step.parameters['withinDays'] as int? ?? 28,
            ),
          );
        case ScenarioStepType.debtPlan:
          final plan = AssistantScenarios.debtPlan(data, step);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${plan.rows.length} выплат · ${money(plan.usedBudgetMinor, plan.request.currency)}',
              ),
              for (final issue in plan.needsConditions) Text(issue),
              for (final shortage in plan.shortages)
                Text(
                  'Нехватка ${money(shortage.amountMinor, plan.request.currency)} · ${shortage.reason}',
                ),
              FilledButton.tonal(
                onPressed: () {
                  AssistantDiagnostics.instance.record(
                    'scenario_plan_opened',
                    values: {'scenarioVersion': scenario.version},
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => DebtPlanningScreen(
                        initialSourceAccountId: plan.request.sourceAccountId,
                        initialBudgetMinor: plan.request.budgetMinor,
                        initialReserveMinor: plan.request.reserveMinor,
                        initialHorizonDays:
                            step.parameters['horizonDays'] as int? ?? 28,
                        initialPlanningWeekday: plan.request.planningWeekday,
                        autoCompute: true,
                      ),
                    ),
                  );
                },
                child: const Text('Проверить полный черновик'),
              ),
            ],
          );
        case ScenarioStepType.showEntries:
          final p = step.parameters;
          final categoryId = p['categoryId'] as String?;
          final accountId = p['accountId'] as String?;
          if (categoryId != null &&
                  !data.categories.any(
                    (c) => c.id == categoryId && !c.archived,
                  ) ||
              accountId != null &&
                  !data.accounts.any((a) => a.id == accountId && !a.archived)) {
            throw const FormatException(
              'Счёт или категория сценария недоступны. Обновите фильтры.',
            );
          }
          final now = DateTime.now();
          final day = DateTime(now.year, now.month, now.day);
          final period = p['period'] ?? 'this_month';
          DateTimeRange? range;
          if (period != 'all') {
            final start = switch (period) {
              'today' => day,
              'yesterday' => DateTime(day.year, day.month, day.day - 1),
              'this_week' => DateTime(
                day.year,
                day.month,
                day.day - (day.weekday - data.preferences.weekStart + 7) % 7,
              ),
              'last_month' => DateTime(day.year, day.month - 1, 1),
              _ => DateTime(day.year, day.month, 1),
            };
            final end = switch (period) {
              'today' || 'yesterday' => start,
              'this_week' => DateTime(start.year, start.month, start.day + 6),
              _ => DateTime(start.year, start.month + 1, 0),
            };
            range = DateTimeRange(start: start, end: end);
          }
          return TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => TransactionsScreen(
                  initialKind: p['kind'] == 'income'
                      ? EntryKind.income
                      : p['kind'] == 'expense'
                      ? EntryKind.expense
                      : null,
                  initialRange: range,
                  categoryId: categoryId,
                  accountId: accountId,
                ),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Показать актуальные операции'),
          );
      }
    } catch (e) {
      return Text(
        userErrorMessage(e),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
  }
}
