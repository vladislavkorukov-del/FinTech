import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../domain/finance_engine.dart';
import '../domain/models.dart';
import 'controller.dart';
import 'haptics.dart';
import 'widgets/amount_format.dart';
import 'widgets/common.dart';
import 'widgets/finora_orb.dart';
import 'widgets/service_badge.dart';
import 'l10n_widgets.dart';

/// Finora asks about the day's payments (1.27): a subscription or a
/// required payment reaches the expenses only after «Оплачено».
abstract final class PaymentPrompt {
  static bool _open = false;

  /// Shows one dialog per due payment, oldest first, until all are answered
  /// or put off.
  static Future<void> check(BuildContext context) async {
    if (_open || !context.mounted) return;
    _open = true;
    try {
      final c = FinanceScope.of(context);
      while (context.mounted) {
        final due = c.duePayments();
        if (due.isEmpty) break;
        final rule = due.first;
        final today = DateTime.now();
        final late = DateTime(today.year, today.month, today.day)
            .difference(
              DateTime(
                rule.nextDate.year,
                rule.nextDate.month,
                rule.nextDate.day,
              ),
            )
            .inDays;
        Finora.react(late > 0 ? FinoraMood.angry : FinoraMood.attention);
        if (!context.mounted) break;
        final answer = await showDialog<_Answer>(
          context: context,
          barrierDismissible: false,
          builder: (_) => FinanceScope(
            controller: c,
            child: _PaymentDialog(rule: rule, late: late),
          ),
        );
        if (!context.mounted) break;
        switch (answer?.action) {
          case 'paid':
            final sum = answer!.amountMinor ?? rule.amountMinor;
            await c.confirmPayment(
              rule.id,
              amountMinor: sum,
              remember: answer.remember,
            );
            Finora.react(
              FinoraMood.done,
              text: 'Записала: ${rule.name} −${money(sum, rule.currency)}',
            );
          case 'skip':
            await c.skipPayment(rule.id);
            Finora.react(FinoraMood.calm, text: 'Хорошо, в этот раз без него.');
          default:
            c.snoozePayment(rule.id);
            Finora.react(FinoraMood.support, text: 'Напомню через пару часов.');
        }
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    } finally {
      _open = false;
    }
  }
}

class _Answer {
  const _Answer(this.action, {this.amountMinor, this.remember = false});
  final String action;
  final int? amountMinor;
  final bool remember;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.rule, required this.late});
  final RecurringRule rule;
  final int late;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

/// 1.36: the sum can be changed — a subscription's price floats.
class _PaymentDialogState extends State<_PaymentDialog> {
  RecurringRule get rule => widget.rule;
  int get late => widget.late;
  late final _amount = TextEditingController(
    text: groupAmount(decimalMinor(widget.rule.amountMinor)),
  );
  late bool remember = widget.rule.paymentType == 'subscription';
  String? error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _sum {
    try {
      final v = FinanceEngine.parseMinor(_amount.text);
      return v > 0 ? v : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final account = c.account(rule.accountId);
    final subscription = rule.paymentType == 'subscription';
    final title = late > 0
        ? 'Платёж просрочен на $late ${_days(late)}!'
        : subscription
        ? 'Сегодня списание подписки'
        : 'Сегодня обязательный платёж';
    return Dialog(
      key: const ValueKey('payment-prompt'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: FinoraCharacter(
                size: 86,
                moods: [late > 0 ? FinoraMood.angry : FinoraMood.attention],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: late > 0 ? scheme.error : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              late > 0
                  ? 'Финора не видит оплату. Оплатили?'
                  : 'Финора спрашивает: уже оплатили? Пока не подтвердите, в '
                        'расходы платёж не попадёт.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SurfaceCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  ServiceBadge(
                    serviceId: rule.serviceId,
                    customIconPath: rule.customIconPath,
                    name: rule.name,
                    icon: rule.icon,
                    iconColor: rule.color,
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rule.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${displayDate(rule.nextDate)}'
                          '${account == null ? '' : ' · ${account.name}'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('payment-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [AmountGroupingFormatter()],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
              decoration: InputDecoration(
                labelText: 'Сколько списали, ${rule.currency}',
                errorText: error,
              ),
              onChanged: (_) => setState(() => error = null),
            ),
            if (_sum != null && _sum != rule.amountMinor)
              CheckboxListTile(
                key: const ValueKey('payment-remember'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: remember,
                onChanged: (v) => setState(() => remember = v ?? false),
                title: const Text('Теперь платёж такой всегда'),
                subtitle: Text(
                  'Было ${money(rule.amountMinor, rule.currency)}',
                ),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const ValueKey('payment-paid'),
              onPressed: () {
                final sum = _sum;
                if (sum == null) {
                  setState(() => error = 'Введите сумму больше нуля');
                  return;
                }
                Haptics.medium();
                Navigator.pop(
                  context,
                  _Answer(
                    'paid',
                    amountMinor: sum,
                    remember: remember && sum != rule.amountMinor,
                  ),
                );
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Оплачено'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('payment-later'),
              onPressed: () => Navigator.pop(context, const _Answer('later')),
              child: const Text('Напомнить позже'),
            ),
            TextButton(
              key: const ValueKey('payment-skip'),
              onPressed: () => Navigator.pop(context, const _Answer('skip')),
              child: const Text('В этот раз не платить'),
            ),
          ],
        ),
      ),
    );
  }

  static String _days(int n) {
    final last = n % 10, lastTwo = n % 100;
    if (last == 1 && lastTwo != 11) return 'день';
    if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) return 'дня';
    return 'дней';
  }
}
