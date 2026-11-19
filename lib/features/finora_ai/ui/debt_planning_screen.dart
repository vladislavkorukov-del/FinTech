import '../../../presentation/screens/developer_screen.dart';
import '../../../domain/monetization.dart';
import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../../../domain/weekly_debt_plan.dart';
import '../../../presentation/controller.dart';
import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/screens/management.dart'
    show CalendarScreen, RecurringScreen;
import '../../../presentation/widgets/common.dart'
    show money, decimalMinor, displayDate, showError;
import '../../../presentation/widgets/grouped_list.dart' show confirmWithFinora;
import '../local_model/assistant_diagnostics.dart';
import '../memory/assistant_preferences.dart';
import '../services/finora_ai.dart';

/// A preview over the existing obligations and calendar, never a second ledger.
class DebtPlanningScreen extends StatefulWidget {
  const DebtPlanningScreen({
    super.key,
    this.initialSourceAccountId,
    this.initialBudgetMinor,
    this.initialReserveMinor,
    this.initialHorizonDays,
    this.initialPlanningWeekday,
    this.autoCompute = false,
  });
  final bool autoCompute;
  final String? initialSourceAccountId;
  final int? initialBudgetMinor,
      initialReserveMinor,
      initialHorizonDays,
      initialPlanningWeekday;
  @override
  State<DebtPlanningScreen> createState() => _DebtPlanningScreenState();
}

class _DebtPlanningScreenState extends State<DebtPlanningScreen> {
  final _budget = TextEditingController();
  final _reserve = TextEditingController();
  String? _account;
  int _days = 28, _weekday = 1;
  bool _initialized = false, _busy = false, _dirty = false, _reminders = false;
  WeeklyDebtPlan? _plan, _previous;
  FinanceData? _previewData;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final memory = FinoraAi.instance.memory.preferences;
    final prefs = memory.plannerParams;
    final data = FinanceScope.of(context).data;
    final proposed =
        widget.initialSourceAccountId ??
        prefs.sourceAccountId ??
        memory.primaryAccountId;
    _account = data.accounts
        .where((a) => a.id == proposed && !a.archived)
        .firstOrNull
        ?.id;
    final amount = widget.initialBudgetMinor ?? prefs.budgetMinor;
    _budget.text = amount == null ? '' : decimalMinor(amount);
    _reserve.text = decimalMinor(
      widget.initialReserveMinor ?? prefs.reserveMinor,
    );
    _days = (widget.initialHorizonDays ?? prefs.horizonDays).clamp(7, 90);
    _weekday = (widget.initialPlanningWeekday ?? memory.planningWeekday).clamp(
      1,
      7,
    );
    if (widget.autoCompute) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _compute();
      });
    }
  }

  @override
  void dispose() {
    _budget.dispose();
    _reserve.dispose();
    super.dispose();
  }

  void _changed() => setState(() => _dirty = true);

  void _compute() {
    try {
      final c = FinanceScope.of(context);
      final account = c.data.accounts
          .where((a) => a.id == _account && !a.archived)
          .firstOrNull;
      if (account == null) {
        throw const FormatException(
          'Выберите счёт, из которого оплачивать долги.',
        );
      }
      final budget = FinanceEngine.parseMinor(_budget.text);
      if (budget <= 0) {
        throw const FormatException(
          'Укажите общий бюджет погашения на выбранный период.',
        );
      }
      final now = DateTime.now();
      final request = WeeklyDebtPlanRequest(
        sourceAccountId: account.id,
        currency: account.currency,
        budgetMinor: budget,
        reserveMinor: FinanceEngine.parseMinor(_reserve.text),
        from: now,
        until: DateTime(now.year, now.month, now.day + _days),
        planningWeekday: _weekday,
      );
      final result = WeeklyDebtPlanner.compute(c.data, request);
      setState(() {
        _previous = _plan;
        _plan = result;
        _previewData = c.data;
        _dirty = false;
      });
      AssistantDiagnostics.instance.record(
        'debt_plan_preview',
        values: {
          'rows': result.rows.length,
          'shortages': result.shortages.length,
          'needsConditions': result.needsConditions.length,
          'canSave': result.canSave,
        },
      );
    } catch (e) {
      showError(context, e);
    }
  }

  Future<void> _save() async {
    final plan = _plan;
    if (_busy || plan == null || !plan.canSave || _dirty) return;
    final c = FinanceScope.of(context);
    setState(() => _busy = true);
    try {
      final approved = await confirmWithFinora(
        context,
        title: 'Сохранить план в календарь?',
        message:
            '${plan.rows.length} выплат · ${money(plan.usedBudgetMinor, plan.request.currency)}\n'
            'Счёт: ${c.account(plan.request.sourceAccountId)?.name ?? ''}\n'
            'Сохранятся только ожидаемые операции. Баланс и фактический долг изменятся после подтверждения оплаты.',
        action: 'Сохранить план',
      );
      if (!approved || !mounted) return;
      await c.mutate((current) {
        var next = plan.applyTo(current);
        if (_reminders) {
          final ids = plan.rows.map((r) => r.ruleId).toSet();
          next = next.copyWith(
            recurring: [
              for (final r in next.recurring)
                ids.contains(r.id) ? r.copyWith(reminderEnabled: true) : r,
            ],
          );
        }
        return next;
      });
      AssistantDiagnostics.instance.record(
        'debt_plan_saved',
        values: {'rows': plan.rows.length, 'remindersRequested': _reminders},
      );
      if (!mounted) return;
      final nav = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      nav.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _reminders && !c.data.preferences.notifications
                ? 'План сохранён. Уведомления выключены в настройках.'
                : 'Ожидаемые выплаты сохранены в календарь.',
          ),
          action: SnackBarAction(
            label: 'Календарь',
            onPressed: () => nav.push<void>(
              MaterialPageRoute<void>(builder: (_) => const CalendarScreen()),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePreferences() async {
    final plan = _plan;
    if (plan == null || _dirty || _busy) return;
    setState(() => _busy = true);
    try {
      final repo = FinoraAi.instance.memoryRepository;
      await repo.setPreferences(
        repo.memory.preferences.copyWith(
          planningWeekday: _weekday,
          plannerParams: PlannerPreferences(
            sourceAccountId: plan.request.sourceAccountId,
            currency: plan.request.currency,
            budgetMinor: plan.request.budgetMinor,
            reserveMinor: plan.request.reserveMinor,
            horizonDays: _days,
          ),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Параметры сохранены по вашему выбору.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveScenario() async {
    final plan = _plan;
    if (plan == null || _dirty || _busy) return;
    setState(() => _busy = true);
    try {
      final repo = FinoraAi.instance.memoryRepository;
      await repo.saveScenario(
        SavedAssistantScenario(
          id: 'debt-plan-${plan.request.sourceAccountId}',
          name: 'Недельный план погашения',
          updatedAt: DateTime.now(),
          requiredData: const ['accounts', 'debts', 'recurring'],
          steps: [
            ScenarioStep(
              type: ScenarioStepType.debtPlan,
              parameters: {
                'sourceAccountId': plan.request.sourceAccountId,
                'currency': plan.request.currency,
                'budgetMinor': plan.request.budgetMinor,
                'reserveMinor': plan.request.reserveMinor,
                'horizonDays': _days,
                'planningWeekday': _weekday,
              },
            ),
          ],
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Сценарий сохранён. При запуске расчёт выполнится заново.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FeatureGate(
    featureId: PaidFeature.debtPlanner,
    child: Builder(builder: _content),
  );

  Widget _content(BuildContext context) {
    final data = FinanceScope.of(context).data;
    final accounts = data.accounts.where((a) => !a.archived).toList();
    final plan = _plan;
    final stale = plan != null && (_dirty || !identical(data, _previewData));
    return Scaffold(
      appBar: AppBar(title: const Text('План погашения')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text(
            'Распределение договорных выплат по календарным неделям. Сначала расчёт, затем подтверждение. Реальные банковские переводы не выполняются.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: const ValueKey('debt-plan-account'),
            isExpanded: true,
            initialValue: accounts.any((a) => a.id == _account)
                ? _account
                : null,
            decoration: const InputDecoration(labelText: 'Источник средств'),
            items: [
              for (final a in accounts)
                DropdownMenuItem(
                  value: a.id,
                  child: Text(
                    '${a.name} · ${a.currency}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    _account = v;
                    _changed();
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('debt-plan-budget'),
            controller: _budget,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(
              labelText: 'Бюджет погашения за весь период',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reserve,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(
              labelText: 'Неприкосновенный резерв',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _days,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Период, дней'),
            items: [
              for (final d in {_days, 7, 14, 28, 30, 60, 90}.toList()..sort())
                DropdownMenuItem(value: d, child: Text('$d')),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    _days = v!;
                    _changed();
                  },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('debt-plan-compute'),
            onPressed: _busy ? null : _compute,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Рассчитать по актуальным данным'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const RecurringScreen(),
                    ),
                  ),
            child: const Text('Долги, кредиты и обязательства'),
          ),
          if (plan != null) ...[
            if (stale)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Данные или параметры изменились. Пересчитайте план перед сохранением.',
                  ),
                ),
              ),
            if (_previous != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Пересчёт: ${_previous!.rows.length} → ${plan.rows.length} выплат; ${money(_previous!.usedBudgetMinor, plan.request.currency)} → ${money(plan.usedBudgetMinor, plan.request.currency)}',
                ),
              ),
            _section('По настроенным договорам', [
              for (final e in plan.debtTotalsByCurrency.entries)
                Text('Вы должны: ${money(e.value, e.key)}'),
              for (final e in plan.receivableTotalsByCurrency.entries)
                Text('Должны вам: ${money(e.value, e.key)}'),
              Text(
                'Выплаты за период: ${money(plan.usedBudgetMinor, plan.request.currency)}',
              ),
              Text(
                'Бюджет не использован: ${money(plan.unusedBudgetMinor, plan.request.currency)}',
              ),
            ]),
            if (plan.rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'В выбранном периоде нет настроенных договорных выплат.',
                ),
              ),
            for (final issue in plan.needsConditions)
              _notice(issue, error: true),
            for (final shortage in plan.shortages)
              _notice(
                '${displayDate(shortage.date)}: не хватает ${money(shortage.amountMinor, plan.request.currency)}. ${shortage.reason}',
                error: true,
              ),
            for (final week in plan.weeks)
              _section(
                'Неделя с ${displayDate(week.start)} · ${money(week.totalMinor, plan.request.currency)}',
                [
                  for (final row in week.rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${row.name} · ${money(row.amountMinor, plan.request.currency)}',
                      ),
                      subtitle: Text(
                        'Выплата ${displayDate(row.proposedDate)}\nДоговорная дата ${displayDate(row.contractualDueDate)}${row.overdue ? ' · просрочено' : ''}\nОжидаемый остаток ${money(row.expectedBalanceMinor, plan.request.currency)}',
                      ),
                    ),
                ],
              ),
            for (final note in [...plan.warnings, ...plan.assumptions])
              _notice(note),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Напоминать о выплатах'),
              subtitle: const Text(
                'Используются напоминания существующих обязательств. Общие настройки уведомлений сохраняются.',
              ),
              value: _reminders,
              onChanged: _busy ? null : (v) => setState(() => _reminders = v),
            ),
            FilledButton(
              key: const ValueKey('debt-plan-save'),
              onPressed: _busy || stale || !plan.canSave ? null : _save,
              child: const Text('Проверить и сохранить ожидаемые выплаты'),
            ),
            TextButton(
              onPressed: _busy || _dirty ? null : _savePreferences,
              child: const Text('Запомнить эти параметры'),
            ),
            TextButton(
              onPressed: _busy || _dirty ? null : _saveScenario,
              child: const Text('Сохранить сценарий для нового расчёта'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _notice(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: error
          ? TextStyle(color: Theme.of(context).colorScheme.error)
          : null,
    ),
  );
  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}
