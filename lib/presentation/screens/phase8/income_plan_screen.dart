import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../../../domain/planning/income_planner.dart';
import '../../controller.dart';
import '../../controller_phase8.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';

/// «Доход и лимиты»: money between irregular incomes — what is free now and
/// once the income comes, a daily limit, the balance by dates, a cash gap,
/// and «what if the payment is late».
class IncomePlanScreen extends StatefulWidget {
  const IncomePlanScreen({super.key});
  @override
  State<IncomePlanScreen> createState() => _IncomePlanScreenState();
}

class _IncomePlanScreenState extends State<IncomePlanScreen> {
  int _delay = 0;
  bool _cancel = false;
  final _reduce = TextEditingController();

  @override
  void dispose() {
    _reduce.dispose();
    super.dispose();
  }

  int _minor(String s) {
    try {
      return s.trim().isEmpty ? 0 : FinanceEngine.parseMinor(s);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _settings(FinanceController c) async {
    final s = c.data.extras.incomePlan;
    final reserve = TextEditingController(
      text: s.reserveMinor == 0
          ? ''
          : decimalMinor(s.reserveMinor).replaceAll('.', ','),
    );
    final horizon = TextEditingController(
      text: s.horizonDays?.toString() ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Резерв и период'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('income-reserve'),
              controller: reserve,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Защищённый резерв, ₽',
              ),
            ),
            TextField(
              key: const ValueKey('income-horizon'),
              controller: horizon,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Период расчёта, дней',
                helperText: 'Пусто — до следующего ожидаемого дохода',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('income-settings-save'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final days = int.tryParse(horizon.text.trim());
      await c.saveIncomePlan(
        IncomePlanSettings(
          reserveMinor: _minor(reserve.text),
          horizonDays: days == null || days <= 0 ? null : days.clamp(1, 120),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cur = c.currency;
    final scenario = IncomeScenario(
      delayDays: _delay,
      reduceMinor: _minor(_reduce.text),
      cancel: _cancel,
    );
    final base = IncomePlanner.plan(c.data);
    final plan = scenario.isNone
        ? base
        : IncomePlanner.plan(c.data, scenario: scenario);
    String d(DateTime x) => '${x.day}.${x.month.toString().padLeft(2, '0')}';
    Widget line(String a, int v, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(a)),
          Text(
            money(v, cur),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    final nextIncome = base.events.where((e) => e.income).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Доход и лимиты'),
        actions: [
          IconButton(
            key: const ValueKey('income-settings'),
            tooltip: 'Резерв и период',
            onPressed: () => _settings(c),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (plan.needsHorizon)
            SurfaceCard(
              key: const ValueKey('income-needs-horizon'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Дата следующего дохода неизвестна. Выберите период расчёта — '
                    'Финора не будет придумывать дату.',
                  ),
                  TextButton(
                    onPressed: () => _settings(c),
                    child: const Text('Выбрать период'),
                  ),
                ],
              ),
            ),
          SurfaceCard(
            key: const ValueKey('income-summary'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Период ${d(plan.start)} — ${d(plan.end.subtract(const Duration(days: 1)))} · ${plan.days} дн.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                line('На счетах сейчас', plan.balanceMinor),
                line('Обязательные платежи', -plan.obligationsMinor),
                if (plan.reserveMinor > 0)
                  line('Защищённый резерв', -plan.reserveMinor),
                const Divider(),
                line('Доступно сейчас', plan.availableNowMinor, bold: true),
                line(
                  'Будет доступно с ожидаемым доходом',
                  plan.availableWithIncomeMinor,
                ),
                const SizedBox(height: 8),
                Text(
                  'Лимит: ${money(plan.dailyLimitMinor, cur)} в день · ${money(plan.weeklyLimitMinor, cur)} в неделю',
                  key: const ValueKey('income-limit'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          if (plan.gapDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SurfaceCard(
                key: const ValueKey('income-gap'),
                child: Text(
                  '${d(plan.gapDate!)} не хватит ${money(plan.gapMinor, cur)} на запланированные платежи.',
                  style: TextStyle(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else if (plan.belowReserveDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${d(plan.belowReserveDate!)} остаток уйдёт в резерв.',
                style: TextStyle(color: scheme.error),
              ),
            ),
          if (plan.sources.isNotEmpty) ...[
            const SectionTitle('Ожидаемые доходы'),
            for (final e in base.events.where((e) => e.income))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.name),
                subtitle: Text('${d(e.date)} · ожидается, ещё не в остатке'),
                trailing: TextButton(
                  key: ValueKey('income-confirm-${e.entryId ?? e.ruleId}'),
                  onPressed: () => c.confirmExpected(
                    entryId: e.entryId,
                    ruleId: e.entryId == null ? e.ruleId : null,
                  ),
                  child: Text('Получен ${money(e.amountMinor, cur)}'),
                ),
              ),
          ],
          if (nextIncome != null) ...[
            SectionTitle('Что если «${nextIncome.name}» задержится'),
            Row(
              children: [
                const Text('Задержка'),
                Expanded(
                  child: Slider(
                    key: const ValueKey('income-delay'),
                    value: _delay.toDouble(),
                    max: 30,
                    divisions: 30,
                    label: '$_delay дн.',
                    onChanged: (v) => setState(() => _delay = v.round()),
                  ),
                ),
                Text('$_delay дн.'),
              ],
            ),
            TextField(
              key: const ValueKey('income-reduce'),
              controller: _reduce,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Меньше на, ₽'),
              onChanged: (_) => setState(() {}),
            ),
            SwitchListTile.adaptive(
              key: const ValueKey('income-cancel'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Доход не придёт'),
              value: _cancel,
              onChanged: (v) => setState(() => _cancel = v),
            ),
            if (!scenario.isNone)
              Text(
                'Это расчёт: операции не меняются.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
          ],
          const SectionTitle('Остаток по датам'),
          if (plan.points.isEmpty)
            const SurfaceCard(
              child: Text('В периоде нет ни платежей, ни ожидаемых доходов.'),
            )
          else
            SurfaceCard(
              key: const ValueKey('income-timeline'),
              child: Column(
                children: [
                  for (final p in plan.points)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 48, child: Text(d(p.date))),
                          Expanded(
                            child: Text(
                              p.events
                                  .map(
                                    (e) =>
                                        '${e.income ? '+' : '−'}${money(e.amountMinor, cur)} ${e.name}${e.scenario.isEmpty ? '' : ' (${e.scenario})'}',
                                  )
                                  .join('\n'),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            money(p.balanceMinor, cur),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: p.balanceMinor < 0 ? scheme.error : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SectionTitle('Допущения'),
          for (final a in plan.assumptions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $a',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
          if (c.data.recurring.where((r) => r.kind == EntryKind.income).isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Добавьте ожидаемые доходы в «Платежи и подписки» (тип «Доход») или '
                'запланированными операциями — они появятся здесь.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
