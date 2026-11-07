part of 'management.dart';

/// «день / дня / дней».
String daysWord(int n) {
  final last = n % 10, lastTwo = n % 100;
  if (last == 1 && lastTwo != 11) return 'день';
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) return 'дня';
  return 'дней';
}

/// 1.36: «Оплачено досрочно» — asks the sum and records the expense today.
/// A full payment moves the next date on; a smaller one only lowers what is
/// left of a loan.
Future<void> payEarly(BuildContext context, RecurringRule rule) async {
  final c = FinanceScope.of(context);
  final plan = PaymentPlan.of(rule, c.data.entries);
  final suggested = plan.hasTotal && plan.leftMinor < rule.amountMinor
      ? plan.leftMinor
      : rule.amountMinor;
  final field = TextEditingController(
    text: groupAmount(decimalMinor(suggested)),
  );
  final sum = await showDialog<int>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          key: const ValueKey('pay-early'),
          icon: const FinoraCharacter(size: 64, moods: [FinoraMood.thinking]),
          title: Text('Оплатить «${rule.name}» досрочно?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                plan.hasTotal
                    ? 'Расход запишется сегодня. Осталось '
                          '${money(plan.leftMinor, rule.currency)}. Полный '
                          'платёж сдвинет дату на следующий период, '
                          'меньшая сумма уменьшит остаток.'
                    : 'Расход запишется сегодня, а следующий платёж '
                          'сдвинется на период вперёд.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('pay-early-amount'),
                controller: field,
                autofocus: false,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [AmountGroupingFormatter()],
                decoration: InputDecoration(
                  labelText: 'Сумма, ${rule.currency}',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const ValueKey('pay-early-confirm'),
              onPressed: () {
                try {
                  final v = FinanceEngine.parseMinor(field.text);
                  if (v <= 0) throw const FormatException('');
                  Navigator.pop(ctx, v);
                } on FormatException {
                  set(() => error = 'Введите сумму больше нуля');
                }
              },
              child: const Text('Оплачено'),
            ),
          ],
        ),
      );
    },
  );
  field.dispose();
  if (sum == null || !context.mounted) return;
  await c.payEarly(rule.id, amountMinor: sum);
  await Haptics.success();
  Finora.react(
    FinoraMood.done,
    text: 'Записала досрочно: ${rule.name} −${money(sum, rule.currency)}',
  );
}

Future<void> openPaymentPlan(BuildContext context, String ruleId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaymentPlanScreen(ruleId: ruleId),
      ),
    );

/// 1.36: a loan or instalment plan — what is left and every payment ahead,
/// «платёж 7 из 12»; late ones in red.
class PaymentPlanScreen extends StatelessWidget {
  const PaymentPlanScreen({super.key, required this.ruleId});
  final String ruleId;

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final rule = c.data.recurring.where((r) => r.id == ruleId).firstOrNull;
    if (rule == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState('Платёж удалён', ''),
      );
    }
    final plan = PaymentPlan.of(rule, c.data.entries);
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Будущие платежи'),
        actions: [
          IconButton(
            tooltip: 'Изменить',
            onPressed: () => showRecurringEditor(context, rule: rule),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ServiceBadge(
                      serviceId: rule.serviceId,
                      customIconPath: rule.customIconPath,
                      name: rule.name,
                      icon: rule.icon,
                      iconColor: rule.color,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(rule.name, style: theme.textTheme.titleLarge),
                    ),
                  ],
                ),
                if (plan.hasTotal) ...[
                  const SizedBox(height: 14),
                  Text(
                    plan.done
                        ? 'Погашено полностью'
                        : 'Осталось ${money(plan.leftMinor, rule.currency)}',
                    key: const ValueKey('plan-left'),
                    style: theme.textTheme.headlineSmall,
                  ),
                  Text(
                    'из ${money(rule.totalMinor!, rule.currency)} · '
                    'оплачено ${money(plan.paidMinor, rule.currency)}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: plan.progress.clamp(0.0, 1.0),
                      minHeight: 8,
                    ),
                  ),
                ],
                if (plan.overdue) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Просрочен на ${plan.overdueDays} '
                    '${daysWord(plan.overdueDays)}',
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (rule.enabled && !plan.done) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('plan-pay-early'),
                    onPressed: () => payEarly(context, rule),
                    icon: const Icon(Icons.bolt_rounded),
                    label: const Text('Оплатить досрочно'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (!plan.done)
            for (final p in plan.upcoming)
              _PlanRow(rule: rule, payment: p, showOf: plan.hasTotal),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.rule,
    required this.payment,
    required this.showOf,
  });
  final RecurringRule rule;
  final PlannedPayment payment;
  final bool showOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final red = payment.overdue ? scheme.error : null;
    return Container(
      key: ValueKey('plan-row-${payment.number}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .3),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Text(
                  '${payment.date.day}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: red),
                ),
                Text(
                  DateFormat(
                    'MMM',
                    AppLanguage.intl,
                  ).format(payment.date).replaceAll('.', ''),
                  style: TextStyle(
                    fontSize: 12,
                    color: red ?? scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ServiceBadge(
            serviceId: rule.serviceId,
            customIconPath: rule.customIconPath,
            name: rule.name,
            icon: rule.icon,
            iconColor: rule.color,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: red),
                ),
                Text(
                  payment.overdue
                      ? 'просрочен'
                      : showOf
                      ? 'платёж ${payment.number} из ${payment.of}'
                      : 'платёж ${payment.number}',
                  style: TextStyle(
                    fontSize: 12,
                    color: red ?? scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            money(payment.amountMinor, rule.currency),
            style: TextStyle(fontWeight: FontWeight.w600, color: red),
          ),
        ],
      ),
    );
  }
}
