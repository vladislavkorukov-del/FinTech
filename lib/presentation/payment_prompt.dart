import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'controller.dart';
import 'haptics.dart';
import 'widgets/common.dart';
import 'widgets/finora_orb.dart';
import 'widgets/service_badge.dart';

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
        final answer = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => FinanceScope(
            controller: c,
            child: _PaymentDialog(rule: rule, late: late),
          ),
        );
        if (!context.mounted) break;
        switch (answer) {
          case 'paid':
            await c.confirmPayment(rule.id);
            Finora.react(
              FinoraMood.done,
              text:
                  'Записала: ${rule.name} −${money(rule.amountMinor, rule.currency)}',
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

class _PaymentDialog extends StatelessWidget {
  const _PaymentDialog({required this.rule, required this.late});
  final RecurringRule rule;
  final int late;

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
                  Text(
                    money(rule.amountMinor, rule.currency),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('payment-paid'),
              onPressed: () {
                Haptics.medium();
                Navigator.pop(context, 'paid');
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Оплачено'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('payment-later'),
              onPressed: () => Navigator.pop(context, 'later'),
              child: const Text('Напомнить позже'),
            ),
            TextButton(
              key: const ValueKey('payment-skip'),
              onPressed: () => Navigator.pop(context, 'skip'),
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
