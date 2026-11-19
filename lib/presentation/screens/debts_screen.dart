import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:intl/intl.dart';

import '../../domain/debt_strategy.dart';
import '../../domain/models.dart';
import '../../domain/payment_plan.dart';
import '../../features/finora_ai/ui/debt_planning_screen.dart';
import '../controller.dart';
import '../i18n.dart';
import '../l10n_widgets.dart';
import '../widgets/common.dart';
import 'debt_editor.dart';
import 'debts_help.dart';
import 'management.dart';

/// «Долги»: everything owed in one place — loans, instalments, personal
/// debts — and what is owed to the person; and Finora's plan to pay them
/// off with the money that is actually free each month. All numbers come
/// from the operations and the payment plans (code, not a model). Planned
/// payments change nothing until they are made.
class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  DebtStrategy _strategy = DebtStrategy.avalanche;
  int? _extra;

  static String monthLabel(int months, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final d = DateTime(clock.year, clock.month + months);
    return DateFormat('LLLL yyyy', AppLanguage.intl).format(d);
  }

  static String duration(int months) {
    final y = months ~/ 12, m = months % 12;
    String plural(int n, String one, String few, String many) {
      final t = n % 100;
      if (t >= 11 && t <= 14) return many;
      return switch (n % 10) {
        1 => one,
        2 || 3 || 4 => few,
        _ => many,
      };
    }

    return [
      if (y > 0) '$y ${plural(y, 'год', 'года', 'лет')}',
      if (m > 0 || y == 0) '$m ${plural(m, 'месяц', 'месяца', 'месяцев')}',
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final currency = c.currency;
    final now = DateTime.now();
    final payable = [
      for (final r in c.data.recurring)
        if (r.kind == EntryKind.expense && (r.totalMinor != null || r.isLoan))
          (r, PaymentPlan.of(r, c.data.entries, now: now)),
    ];
    final receivable = [
      for (final r in c.data.recurring)
        if (r.kind == EntryKind.income && r.totalMinor != null)
          (r, PaymentPlan.of(r, c.data.entries, now: now)),
    ];
    int sum(List<(RecurringRule, PaymentPlan)> list) => list
        .where((p) => p.$1.currency == currency)
        .fold(0, (a, p) => a + p.$2.leftMinor);
    final owed = sum(payable), owedToMe = sum(receivable);
    final debts = DebtStrategies.debtsOf(c.data, currency: currency, now: now);
    final capacity = DebtStrategies.capacity(
      c.data,
      currency: currency,
      now: now,
    );
    final extra = (_extra ?? capacity.suggestedExtraMinor).clamp(0, 1 << 40);
    final plans = debts.isEmpty
        ? const <DebtPayoff>[]
        : DebtStrategies.compare(debts, extra);
    final chosen = plans.where((p) => p.strategy == _strategy).firstOrNull;
    final base = plans.where((p) => p.strategy == null).firstOrNull;
    final best = plans.firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Долги')),
        actions: [
          IconButton(
            key: const ValueKey('debts-help-button'),
            tooltip: 'Как пользоваться',
            onPressed: () => showDebtsHelp(context),
            icon: const Icon(Icons.help_outline_rounded),
          ),
          IconButton(
            key: const ValueKey('debts-add'),
            tooltip: 'Добавить долг',
            onPressed: () => showDebtEditor(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: _Total(
                  key: const ValueKey('debts-owed'),
                  title: 'Я должен',
                  amount: money(owed, currency),
                  color: scheme.error,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Total(
                  key: const ValueKey('debts-owed-to-me'),
                  title: 'Мне должны',
                  amount: money(owedToMe, currency),
                  color: Colors.green.shade600,
                ),
              ),
            ],
          ),
          if (payable.isEmpty && receivable.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: SurfaceCard(
                onTap: () => showDebtEditor(context),
                child: const EmptyState(
                  'Долгов нет',
                  'Добавьте кредит, рассрочку или долг человеку — Финора '
                      'посчитает, как закрыть их быстрее и дешевле.',
                  icon: Icons.handshake_outlined,
                ),
              ),
            ),
          if (payable.isEmpty && receivable.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                key: const ValueKey('debts-help-empty'),
                onPressed: () => showDebtsHelp(context),
                icon: const Icon(Icons.lightbulb_outline_rounded),
                label: const Text('Как это работает — с примерами'),
              ),
            ),
          if (payable.isNotEmpty) ...[
            SectionTitle(tr('Мои долги')),
            for (final (r, plan) in payable)
              _DebtRow(
                rule: r,
                plan: plan,
                closesIn: chosen?.payoffMonth[r.id],
              ),
          ],
          if (receivable.isNotEmpty) ...[
            SectionTitle(tr('Мне должны')),
            for (final (r, plan) in receivable) _DebtRow(rule: r, plan: plan),
          ],
          if (debts.isNotEmpty) ...[
            SectionTitle(tr('План Финоры')),
            _capacityCard(context, capacity, currency),
            const SizedBox(height: 12),
            Text(
              'Сверх обязательных платежей в месяц: ${money(extra, currency)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Slider(
              key: const ValueKey('debts-extra'),
              value: extra.toDouble().clamp(0, _maxExtra(capacity, debts)),
              max: _maxExtra(capacity, debts),
              divisions: 40,
              label: money(extra, currency),
              onChanged: (v) => setState(() => _extra = (v ~/ 10000) * 10000),
            ),
            SegmentedButton<DebtStrategy>(
              key: const ValueKey('debts-strategy'),
              segments: const [
                ButtonSegment(
                  value: DebtStrategy.avalanche,
                  label: Text('Лавина'),
                  icon: Icon(Icons.percent_rounded),
                ),
                ButtonSegment(
                  value: DebtStrategy.snowball,
                  label: Text('Снежный ком'),
                  icon: Icon(Icons.ac_unit_rounded),
                ),
              ],
              selected: {_strategy},
              onSelectionChanged: (s) => setState(() => _strategy = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              _strategy == DebtStrategy.avalanche
                  ? 'Сначала самый дорогой по ставке — меньше всего переплата.'
                  : 'Сначала самый маленький — первый долг закроется быстрее.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            if (chosen != null)
              _PlanCard(
                plan: chosen,
                base: base,
                debts: debts,
                currency: currency,
                recommended: best?.strategy == _strategy,
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('debts-weekly'),
              onPressed: () =>
                  openFinancePage(context, const DebtPlanningScreen()),
              icon: const Icon(Icons.calendar_view_week_rounded),
              label: const Text('Недельный график платежей'),
            ),
          ],
        ],
      ),
    );
  }

  static double _maxExtra(DebtCapacity capacity, List<DebtItem> debts) {
    final owed = debts.fold<int>(0, (a, d) => a + d.balanceMinor);
    final free = capacity.freeMinor;
    final top = free > 0 ? free : owed ~/ 12;
    return (top <= 0 ? 1000000 : top).toDouble();
  }

  Widget _capacityCard(
    BuildContext context,
    DebtCapacity capacity,
    String currency,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (capacity.months == 0) {
      return const SurfaceCard(
        child: Text(
          'Пока мало истории, чтобы понять, сколько свободно в месяц. '
          'Задайте сумму вручную.',
        ),
      );
    }
    Widget line(String a, int v, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(a)),
          Text(
            money(v, currency),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return SurfaceCard(
      key: const ValueKey('debts-capacity'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'В среднем за ${capacity.months} мес.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 6),
          line('Доходы', capacity.incomeMinor),
          line('Повседневные расходы', -capacity.spendingMinor),
          line('Обязательные платежи по долгам', -capacity.minimumsMinor),
          const Divider(),
          line('Свободно в месяц', capacity.freeMinor, bold: true),
          if (capacity.freeMinor <= 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Денег на досрочное погашение сейчас не остаётся. Начните с '
                'сокращения расходов или договоритесь о меньшем платеже.',
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Финора предлагает отдавать половину свободных денег, '
                'вторая половина — запас на непредвиденное.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    super.key,
    required this.title,
    required this.amount,
    required this.color,
  });
  final String title, amount;
  final Color color;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: color, fontSize: 13)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            amount,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

class _DebtRow extends StatelessWidget {
  const _DebtRow({required this.rule, required this.plan, this.closesIn});
  final RecurringRule rule;
  final PaymentPlan plan;
  final int? closesIn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = [
      if (rule.isLoan) '${rule.interestRate!.toStringAsFixed(1)} %',
      if (rule.amountMinor > 0)
        '${money(rule.amountMinor, rule.currency)} / мес.',
      if (plan.overdue) 'просрочка ${plan.overdueDays} дн.',
      if (closesIn != null)
        'закроется в ${_DebtsScreenState.monthLabel(closesIn!)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        key: ValueKey('debt-${rule.id}'),
        onTap: () => openPaymentPlan(context, rule.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    rule.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  money(plan.leftMinor, rule.currency),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (plan.hasTotal) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: plan.progress.clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: scheme.onSurface.withValues(alpha: .08),
                ),
              ),
            ],
            if (details.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                details.join(' · '),
                style: TextStyle(
                  fontSize: 13,
                  color: plan.overdue ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.base,
    required this.debts,
    required this.currency,
    required this.recommended,
  });
  final DebtPayoff plan;
  final DebtPayoff? base;
  final List<DebtItem> debts;
  final String currency;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final names = {for (final d in debts) d.id: d.name};
    final first = plan.schedule.firstOrNull;
    final saved = base != null && base!.finished && plan.finished
        ? base!.totalInterestMinor - plan.totalInterestMinor
        : null;
    final sooner = base != null && base!.finished && plan.finished
        ? base!.months - plan.months
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SurfaceCard(
        key: const ValueKey('debts-plan'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (recommended)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Рекомендую: так выгоднее',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            Text(
              plan.finished
                  ? 'Без долгов к ${_DebtsScreenState.monthLabel(plan.months)}'
                  : 'Такими платежами долги не закрыть',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            if (plan.finished)
              Text(
                'Через ${_DebtsScreenState.duration(plan.months)} · проценты '
                '${money(plan.totalInterestMinor, currency)}',
              )
            else
              Text(
                'Платёж меньше начисляемых процентов или у долга нет платежа. '
                'Добавьте сумму сверх минимума.',
                style: TextStyle(color: scheme.error),
              ),
            if (saved != null && sooner != null && (saved > 0 || sooner > 0))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'По сравнению с одними минимальными платежами: '
                  '${sooner > 0 ? 'на ${_DebtsScreenState.duration(sooner)} раньше' : 'в тот же срок'}'
                  '${saved > 0 ? ', переплата меньше на ${money(saved, currency)}' : ''}.',
                  style: TextStyle(color: Colors.green.shade700),
                ),
              ),
            if (first != null) ...[
              const SizedBox(height: 10),
              Text(
                'В этом месяце',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final e in first.payments.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(names[e.key] ?? '')),
                      Text(
                        money(e.value, currency),
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (plan.order.length > 1) ...[
              const SizedBox(height: 10),
              Text(
                'Порядок: ${plan.order.map((id) => names[id]).join(' → ')}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Расчёт по вашим операциям и условиям долгов; ставки и комиссии '
              'банка могут отличаться. Деньги никуда не переводятся.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
