import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/finance_engine.dart';
import '../../../domain/planning/data_health.dart';
import '../../controller.dart';
import '../../controller_phase8.dart';
import '../../l10n_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/grouped_list.dart' show confirmWithFinora;
import '../entry_editor.dart';

/// «Проверка данных» — the honest picture: when each balance was checked,
/// reconciliation with the bank, what is unconfirmed, uncategorized, maybe
/// duplicated, which expected incomes the forecast counts, and its limits.
class DataHealthScreen extends StatelessWidget {
  const DataHealthScreen({super.key});

  Future<void> _reconcile(BuildContext context, AccountCheck a) async {
    final c = FinanceScope.of(context);
    final field = TextEditingController();
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Сверка «${a.account.name}»'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('В учёте: ${money(a.bookMinor, a.account.currency)}'),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('reconcile-actual'),
              controller: field,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Сколько сейчас в банке',
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
            key: const ValueKey('reconcile-save'),
            onPressed: () {
              try {
                Navigator.pop(ctx, FinanceEngine.parseMinor(field.text));
              } catch (_) {}
            },
            child: const Text('Сверить'),
          ),
        ],
      ),
    );
    if (value == null || !context.mounted) return;
    final r = await c.reconcile(a.account.id, value);
    if (!context.mounted) return;
    if (r.differenceMinor == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Совпадает с банком. Дата сверки сохранена.'),
        ),
      );
      return;
    }
    final adjust = await confirmWithFinora(
      context,
      title: 'Расхождение ${money(r.differenceMinor, a.account.currency)}',
      message:
          'В учёте ${money(r.bookMinor, a.account.currency)}, в банке '
          '${money(r.actualMinor, a.account.currency)}. Причина неизвестна: '
          'проверьте операции счёта. Можно создать явную корректировку — она '
          'не считается доходом или расходом и видна в истории.',
      action: 'Создать корректировку',
      cancel: 'Проверю операции',
    );
    if (adjust) await c.adjustBalance(r.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final report = DataHealth.check(c.data, now: now);
    final recs = [...c.data.extras.reconciliations]
      ..sort((a, b) => b.at.compareTo(a.at));
    Widget issue(DataIssue i) => ListTile(
      key: ValueKey('issue-${i.kind}-${i.entryId ?? i.accountId}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(switch (i.kind) {
        'duplicate' => Icons.copy_all_rounded,
        'uncategorized' => Icons.category_outlined,
        'unconfirmed' => Icons.schedule_rounded,
        'expected' => Icons.south_west_rounded,
        'difference' => Icons.balance_rounded,
        _ => Icons.history_toggle_off_rounded,
      }, color: scheme.primary),
      title: Text(i.text, style: const TextStyle(fontSize: 14)),
      trailing: i.entryId != null
          ? const Icon(Icons.chevron_right_rounded)
          : null,
      onTap: i.entryId == null
          ? null
          : () {
              final e = c.data.entries
                  .where((x) => x.id == i.entryId)
                  .firstOrNull;
              if (e != null) showEntryEditor(context, entry: e);
            },
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Проверка данных')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const SectionTitle('Остатки счетов'),
          for (final a in report.accounts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                key: ValueKey('health-account-${a.account.id}'),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.account.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            a.last == null
                                ? 'Ещё не сверялся с банком'
                                : 'Сверен ${a.daysSince(now) == 0 ? 'сегодня' : '${a.daysSince(now)} дн. назад'}'
                                      '${a.last!.differenceMinor == 0 ? ' · совпал' : ' · разница ${money(a.last!.differenceMinor, a.account.currency)}'}',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(money(a.bookMinor, a.account.currency)),
                    TextButton(
                      key: ValueKey('reconcile-${a.account.id}'),
                      onPressed: () => _reconcile(context, a),
                      child: const Text('Сверить'),
                    ),
                  ],
                ),
              ),
            ),
          const SectionTitle('Что требует проверки'),
          if (report.issues.isEmpty)
            const SurfaceCard(child: Text('Проблем в данных не найдено.'))
          else
            SurfaceCard(
              child: Column(
                children: [for (final i in report.issues) issue(i)],
              ),
            ),
          const SectionTitle('На чём основан прогноз'),
          SurfaceCard(
            key: const ValueKey('health-limits'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in report.limits)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('• $l'),
                  ),
              ],
            ),
          ),
          if (recs.isNotEmpty) ...[
            const SectionTitle('История сверок'),
            SurfaceCard(
              child: Column(
                children: [
                  for (final r in recs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.account(r.accountId)?.name ?? 'Счёт'),
                      subtitle: Text(
                        '${r.at.day}.${r.at.month.toString().padLeft(2, '0')}.${r.at.year}: учёт ${money(r.bookMinor, c.currency)}, банк ${money(r.actualMinor, c.currency)}'
                        '${r.adjustmentEntryId != null ? ' · корректировка создана' : ''}',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
