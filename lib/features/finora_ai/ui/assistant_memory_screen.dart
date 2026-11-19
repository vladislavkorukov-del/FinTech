import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finance_engine.dart';
import '../../../presentation/controller.dart';
import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/widgets/common.dart'
    show confirm, decimalMinor, money, showError;
import '../memory/assistant_preferences.dart';
import '../repositories/memory_repository.dart';
import '../services/finora_ai.dart';

/// Explicitly confirmed local preferences and typed reusable plans. This is
/// the existing personal-memory repository, not another account or AI store.
class AssistantMemoryScreen extends StatefulWidget {
  const AssistantMemoryScreen({super.key, this.repository, this.onRun});
  final MemoryRepository? repository;
  final Future<void> Function(SavedAssistantScenario)? onRun;
  @override
  State<AssistantMemoryScreen> createState() => _AssistantMemoryScreenState();
}

class _AssistantMemoryScreenState extends State<AssistantMemoryScreen> {
  late final repo = widget.repository ?? FinoraAi.instance.memoryRepository;
  late final ready = repo.load();
  bool busy = false;
  static const weekdays = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];
  static const stepNames = {
    ScenarioStepType.summary: 'Финансовый обзор',
    ScenarioStepType.upcomingPayments: 'Ближайшие платежи',
    ScenarioStepType.debtPlan: 'Черновик плана погашения',
    ScenarioStepType.showEntries: 'Показать операции',
  };

  Future<void> _run(Future<void> Function() task) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _preferences() async {
    final old = repo.memory.preferences;
    final p = await _editPreferences(old);
    if (p == null || !mounted) return;
    await _run(() => repo.setPreferences(p));
  }

  Future<AssistantPreferences?> _editPreferences(
    AssistantPreferences old, {
    bool plannerOnly = false,
  }) async {
    final accounts = FinanceScope.of(
      context,
    ).data.accounts.where((a) => !a.archived).toList();
    var primary = old.primaryAccountId;
    var source = old.plannerParams.sourceAccountId;
    var weekday = old.planningWeekday;
    var format = old.reportFormat;
    final currency = TextEditingController(text: old.plannerParams.currency);
    final budget = TextEditingController(
      text: old.plannerParams.budgetMinor == null
          ? ''
          : decimalMinor(old.plannerParams.budgetMinor!),
    );
    final reserve = TextEditingController(
      text: decimalMinor(old.plannerParams.reserveMinor),
    );
    final horizon = TextEditingController(
      text: '${old.plannerParams.horizonDays}',
    );
    String? error;
    try {
      final route = DialogRoute<AssistantPreferences>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) {
            Widget accountField(
              String title,
              String? value,
              void Function(String?) changed,
            ) => DropdownButtonFormField<String>(
              initialValue: value ?? '',
              isExpanded: true,
              decoration: InputDecoration(labelText: title),
              items: [
                const DropdownMenuItem(value: '', child: Text('Не выбран')),
                for (final a in accounts)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text(a.name, overflow: TextOverflow.ellipsis),
                  ),
                if (value != null && !accounts.any((a) => a.id == value))
                  DropdownMenuItem(
                    value: value,
                    child: const Text('Счёт недоступен — выберите другой'),
                  ),
              ],
              onChanged: (v) => update(() => changed(v == '' ? null : v)),
            );
            return AlertDialog(
              title: Text(
                plannerOnly
                    ? 'Параметры сценария'
                    : 'Подтверждённые предпочтения',
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!plannerOnly)
                        accountField(
                          'Какой счёт называть основным',
                          primary,
                          (v) => primary = v,
                        ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: weekday,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'День планирования',
                        ),
                        items: [
                          for (var i = 0; i < 7; i++)
                            DropdownMenuItem(
                              value: i + 1,
                              child: Text(weekdays[i]),
                            ),
                        ],
                        onChanged: (v) =>
                            update(() => weekday = v ?? DateTime.monday),
                      ),
                      const SizedBox(height: 12),
                      if (!plannerOnly)
                        DropdownButtonFormField<AssistantReportFormat>(
                          initialValue: format,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Формат отчёта',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: AssistantReportFormat.brief,
                              child: Text('Краткий'),
                            ),
                            DropdownMenuItem(
                              value: AssistantReportFormat.detailed,
                              child: Text('Подробный'),
                            ),
                          ],
                          onChanged: (v) => update(
                            () => format = v ?? AssistantReportFormat.brief,
                          ),
                        ),
                      const SizedBox(height: 20),
                      accountField(
                        'Источник средств для плана',
                        source,
                        (v) => source = v,
                      ),
                      TextField(
                        controller: currency,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 3,
                        decoration: const InputDecoration(
                          labelText: 'Валюта плана',
                        ),
                      ),
                      TextField(
                        controller: budget,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Бюджет погашения за весь период',
                          hintText: 'Не задан',
                        ),
                      ),
                      TextField(
                        controller: reserve,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Резерв на счёте',
                        ),
                      ),
                      TextField(
                        controller: horizon,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Период плана, дней (7–90)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Эти параметры не запускают расчёты или платежи по расписанию.',
                      ),
                      if (error != null)
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () {
                    try {
                      final next = AssistantPreferences(
                        primaryAccountId: primary,
                        planningWeekday: weekday,
                        reportFormat: format,
                        plannerParams: PlannerPreferences(
                          sourceAccountId: source,
                          currency: currency.text.trim().toUpperCase(),
                          budgetMinor: budget.text.trim().isEmpty
                              ? null
                              : FinanceEngine.parseMinor(budget.text),
                          reserveMinor: FinanceEngine.parseMinor(reserve.text),
                          horizonDays: int.tryParse(horizon.text) ?? 0,
                        ),
                      );
                      Navigator.pop(dialogContext, next);
                    } on FormatException catch (e) {
                      update(() => error = e.message);
                    }
                  },
                  child: const Text('Подтвердить и сохранить'),
                ),
              ],
            );
          },
        ),
      );
      final result = await Navigator.of(context).push(route);
      await route.completed;
      return result;
    } finally {
      currency.dispose();
      budget.dispose();
      reserve.dispose();
      horizon.dispose();
    }
  }

  Future<void> _scenario([SavedAssistantScenario? existing]) async {
    final name = TextEditingController(
      text: existing?.name ?? 'Недельный разбор',
    );
    final steps = <ScenarioStep>[
      ...existing?.steps ??
          [
            ScenarioStep(
              type: ScenarioStepType.summary,
              parameters: {'period': 'week'},
            ),
            ScenarioStep(
              type: ScenarioStepType.upcomingPayments,
              parameters: {'withinDays': 7},
            ),
          ],
    ];
    String? error;
    final route = DialogRoute<SavedAssistantScenario>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            existing == null ? 'Сохранить сценарий' : 'Изменить сценарий',
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Название'),
                  ),
                  for (final type in ScenarioStepType.values)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(stepNames[type]!),
                      value: steps.any((s) => s.type == type),
                      onChanged: (v) => update(() {
                        if (v == true && !steps.any((s) => s.type == type)) {
                          final params = switch (type) {
                            ScenarioStepType.summary => <String, dynamic>{
                              'period': 'week',
                            },
                            ScenarioStepType.upcomingPayments =>
                              <String, dynamic>{'withinDays': 7},
                            ScenarioStepType.debtPlan => <String, dynamic>{
                              ...repo.memory.preferences.plannerParams.toJson(),
                              'planningWeekday':
                                  repo.memory.preferences.planningWeekday,
                            },
                            ScenarioStepType.showEntries => <String, dynamic>{
                              'period': 'this_week',
                            },
                          };
                          steps.add(
                            ScenarioStep(type: type, parameters: params),
                          );
                        } else if (v != true) {
                          steps.removeWhere((s) => s.type == type);
                        }
                      }),
                    ),
                  for (var i = 0; i < steps.length; i++) ...[
                    Text('${i + 1}. ${stepNames[steps[i].type]}'),
                    if (steps[i].type == ScenarioStepType.summary)
                      DropdownButtonFormField<String>(
                        initialValue:
                            steps[i].parameters['period'] as String? ?? 'week',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Период обзора',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'week',
                            child: Text('Текущая неделя'),
                          ),
                          DropdownMenuItem(
                            value: 'month',
                            child: Text('Текущий месяц'),
                          ),
                        ],
                        onChanged: (v) => update(
                          () => steps[i] = ScenarioStep(
                            type: ScenarioStepType.summary,
                            parameters: {'period': v ?? 'week'},
                          ),
                        ),
                      ),
                    if (steps[i].type == ScenarioStepType.upcomingPayments)
                      DropdownButtonFormField<int>(
                        initialValue:
                            steps[i].parameters['withinDays'] as int? ?? 28,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Платежи за сколько дней',
                        ),
                        items: [
                          for (var day = 1; day <= 90; day++)
                            DropdownMenuItem(
                              value: day,
                              child: Text('$day дней'),
                            ),
                        ],
                        onChanged: (v) => update(
                          () => steps[i] = ScenarioStep(
                            type: ScenarioStepType.upcomingPayments,
                            parameters: {'withinDays': v ?? 28},
                          ),
                        ),
                      ),
                    if (steps[i].type == ScenarioStepType.showEntries) ...[
                      DropdownButtonFormField<String>(
                        initialValue:
                            steps[i].parameters['period'] as String? ??
                            'this_month',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Период операций',
                        ),
                        items: [
                          for (final p in const {
                            'today': 'Сегодня',
                            'yesterday': 'Вчера',
                            'this_week': 'Эта неделя',
                            'this_month': 'Этот месяц',
                            'last_month': 'Прошлый месяц',
                            'all': 'Всё время',
                          }.entries)
                            DropdownMenuItem(
                              value: p.key,
                              child: Text(p.value),
                            ),
                        ],
                        onChanged: (v) => update(
                          () => steps[i] = ScenarioStep(
                            type: ScenarioStepType.showEntries,
                            parameters: {
                              ...steps[i].parameters,
                              'period': v ?? 'this_month',
                            },
                          ),
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue:
                            steps[i].parameters['kind'] as String? ?? 'all',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Тип операций',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Все')),
                          DropdownMenuItem(
                            value: 'expense',
                            child: Text('Расходы'),
                          ),
                          DropdownMenuItem(
                            value: 'income',
                            child: Text('Доходы'),
                          ),
                        ],
                        onChanged: (v) => update(() {
                          final params = Map<String, dynamic>.from(
                            steps[i].parameters,
                          )..remove('categoryId');
                          if (v == 'all') {
                            params.remove('kind');
                          } else {
                            params['kind'] = v;
                          }
                          steps[i] = ScenarioStep(
                            type: ScenarioStepType.showEntries,
                            parameters: params,
                          );
                        }),
                      ),
                    ],
                    if (steps[i].type == ScenarioStepType.debtPlan)
                      TextButton(
                        onPressed: () async {
                          final values = Map<String, dynamic>.from(
                            steps[i].parameters,
                          )..remove('planningWeekday');
                          final p = await _editPreferences(
                            repo.memory.preferences.copyWith(
                              plannerParams: PlannerPreferences.fromJson(
                                values,
                              ),
                              planningWeekday:
                                  steps[i].parameters['planningWeekday']
                                      as int? ??
                                  repo.memory.preferences.planningWeekday,
                            ),
                            plannerOnly: true,
                          );
                          if (p != null && context.mounted) {
                            update(
                              () => steps[i] = ScenarioStep(
                                type: ScenarioStepType.debtPlan,
                                parameters: {
                                  ...p.plannerParams.toJson(),
                                  'planningWeekday': p.planningWeekday,
                                },
                              ),
                            );
                          }
                        },
                        child: const Text('Изменить параметры плана'),
                      ),
                  ],
                  const Text(
                    'При запуске читаются актуальные данные. Сохранение не включает расписание и не проводит платежи.',
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(
                    dialogContext,
                    SavedAssistantScenario(
                      id:
                          existing?.id ??
                          'scenario-${DateTime.now().microsecondsSinceEpoch}',
                      name: name.text.trim(),
                      steps: steps,
                      requiredData: existing?.requiredData ?? ['finance'],
                      updatedAt: DateTime.now(),
                    ),
                  );
                } on FormatException catch (e) {
                  update(() => error = e.message);
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    final next = await Navigator.of(context).push(route);
    await route.completed;
    name.dispose();
    if (next != null && mounted) await _run(() => repo.saveScenario(next));
  }

  String _stepDescription(ScenarioStep step) {
    final p = step.parameters;
    final data = FinanceScope.of(context).data;
    String account(Object? id) => id == null
        ? 'будет выбран при запуске'
        : data.accounts.where((a) => a.id == id).firstOrNull?.name ??
              'счёт недоступен';
    return switch (step.type) {
      ScenarioStepType.summary =>
        p['period'] == 'month' ? 'Текущий месяц' : 'Текущая неделя',
      ScenarioStepType.upcomingPayments =>
        'Ближайшие ${p['withinDays'] ?? 28} дней',
      ScenarioStepType.debtPlan =>
        'Источник: ${account(p['sourceAccountId'])}\n'
            'Бюджет: ${p['budgetMinor'] == null ? 'уточнить при запуске' : money(p['budgetMinor'] as int, p['currency'] as String? ?? 'RUB')}\n'
            'Резерв: ${money(p['reserveMinor'] as int? ?? 0, p['currency'] as String? ?? 'RUB')}\n'
            'Период: ${p['horizonDays'] ?? 28} дней',
      ScenarioStepType.showEntries =>
        'Тип: ${p['kind'] == 'income'
                ? 'доходы'
                : p['kind'] == 'expense'
                ? 'расходы'
                : 'все операции'}\n'
            'Период: ${const {'today': 'сегодня', 'yesterday': 'вчера', 'this_week': 'эта неделя', 'this_month': 'этот месяц', 'last_month': 'прошлый месяц', 'all': 'всё время'}[p['period']] ?? 'этот месяц'}'
            '${p['accountId'] == null ? '' : '\nСчёт: ${account(p['accountId'])}'}',
    };
  }

  Future<void> _details(
    SavedAssistantScenario scenario,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(scenario.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (var i = 0; i < scenario.steps.length; i++) ...[
              Text('${i + 1}. ${stepNames[scenario.steps[i].type]}'),
              Text(
                _stepDescription(scenario.steps[i]),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Версия ${scenario.version} · изменён ${scenario.updatedAt.toLocal().toString().split('.').first}',
            ),
            const Text(
              'Текущие суммы будут рассчитаны заново. Автозапуск не включён.',
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Память и сценарии')),
    body: FutureBuilder(
      future: ready,
      builder: (context, done) {
        if (done.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final preferences = repo.memory.preferences;
        final data = FinanceScope.of(context).data;
        final primary = data.accounts
            .where((a) => a.id == preferences.primaryAccountId)
            .firstOrNull;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if (repo.readError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(repo.readError!.message),
              ),
            const Text(
              'Подтверждённые предпочтения',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Основной счёт'),
              subtitle: Text(
                primary?.name ??
                    (preferences.primaryAccountId == null
                        ? 'Не выбран'
                        : 'Счёт недоступен'),
              ),
            ),
            Text(
              '${weekdays[preferences.planningWeekday - 1]} · ${preferences.reportFormat == AssistantReportFormat.brief ? 'Краткий отчёт' : 'Подробный отчёт'}',
            ),
            Text(
              'Бюджет плана: ${preferences.plannerParams.budgetMinor == null ? 'не задан' : money(preferences.plannerParams.budgetMinor!, preferences.plannerParams.currency)}',
            ),
            FilledButton.tonal(
              onPressed: busy || repo.readError != null ? null : _preferences,
              child: const Text('Изменить предпочтения'),
            ),
            TextButton(
              onPressed: busy || repo.readError != null
                  ? null
                  : () async {
                      if (await confirm(
                        context,
                        'Удалить предпочтения?',
                        'Счета, операции и сохранённые сценарии останутся.',
                      )) {
                        await _run(
                          () => repo.setPreferences(AssistantPreferences()),
                        );
                      }
                    },
              child: const Text('Удалить предпочтения'),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Сохранённые сценарии',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: busy || repo.readError != null ? null : _scenario,
                  icon: const Icon(Icons.add),
                  tooltip: 'Создать сценарий',
                ),
              ],
            ),
            if (repo.memory.scenarios.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Сценариев пока нет. Сохраните разбор, чтобы повторять его на актуальных данных.',
                ),
              ),
            for (final scenario in repo.memory.scenarios)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(scenario.name),
                        subtitle: Text(
                          '${scenario.steps.length} шага · без автозапуска',
                        ),
                        onTap: () => _details(scenario),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (widget.onRun != null)
                            FilledButton.tonal(
                              onPressed: busy
                                  ? null
                                  : () => _run(() => widget.onRun!(scenario)),
                              child: const Text('Запустить'),
                            ),
                          TextButton(
                            onPressed: busy ? null : () => _scenario(scenario),
                            child: const Text('Изменить'),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    if (await confirm(
                                      context,
                                      'Удалить сценарий?',
                                      scenario.name,
                                    )) {
                                      await _run(
                                        () => repo.deleteScenario(scenario.id),
                                      );
                                    }
                                  },
                            child: const Text('Удалить'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (widget.onRun == null && repo.memory.scenarios.isNotEmpty)
              const Text('Запуск сценария доступен из диалога с Финорой.'),
            const SizedBox(height: 24),
            const Text(
              'Мои сокращения',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                'Как вы называете места. Научить: «кб — это Красное и Белое» '
                'в чате, или исправьте «Кб» на полное название в форме.',
              ),
            ),
            if (repo.memory.aliases.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Пока нет.'),
              ),
            for (final alias in repo.memory.aliases.entries)
              ListTile(
                key: ValueKey('alias-${alias.key}'),
                contentPadding: EdgeInsets.zero,
                title: Text('«${alias.key}» → ${alias.value}'),
                trailing: IconButton(
                  tooltip: 'Забыть',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                          repo.memory.aliases.remove(alias.key);
                          await repo.save();
                        }),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Это локальная память подтверждённых настроек, а не обучение весов Qwen. Удаление модели не удаляет память.',
            ),
          ],
        );
      },
    ),
  );
}
