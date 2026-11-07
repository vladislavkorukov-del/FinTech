import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../controller.dart';
import '../screens/entry_editor.dart';
import 'common.dart';
import 'service_badge.dart';
import '../../domain/service_catalog.dart';

class EntryTile extends StatelessWidget {
  const EntryTile(this.entry, {super.key, this.swipe = true, this.onTap});
  final FinanceEntry entry;
  final bool swipe;

  /// Overrides the default «open editor» tap (the dashboard opens a payee
  /// summary instead).
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final cat = c.category(entry.categoryId);
    final transfer = entry.kind == EntryKind.transfer;
    final income = entry.kind == EntryKind.income;
    // 1.36: a payment's operation shows the payment's own icon.
    final rule = transfer ? null : c.ruleOf(entry);
    final ruleIcon =
        rule != null &&
        (rule.icon != null ||
            rule.customIconPath != null ||
            rule.serviceId != null);
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      leading: ruleIcon
          ? ServiceBadge(
              serviceId: rule.serviceId,
              customIconPath: rule.customIconPath,
              name: rule.name,
              icon: rule.icon,
              iconColor: rule.color,
            )
          : !transfer &&
                (entry.serviceId != null ||
                    entry.serviceIconPath != null ||
                    ServiceCatalog.byName(entry.payee) != null)
          ? ServiceBadge(
              serviceId: entry.serviceId,
              customIconPath: entry.serviceIconPath,
              name: entry.payee,
            )
          : CategoryBadge(
              category: cat,
              icon: transfer ? Icons.swap_horiz_rounded : null,
            ),
      title: Text(
        entry.payee.isEmpty ? (cat?.name ?? 'Перевод') : entry.payee,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Text(
        '${transfer ? '${c.account(entry.accountId)?.name} → ${c.destinationName(entry)}' : cat?.name ?? ''} · ${DateFormat('d MMM', 'ru').format(entry.date)}${entry.status == 'posted'
            ? ''
            : entry.status == 'pending'
            ? ' · ожидает'
            : ' · отменена'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .39,
        ),
        child: Text(
          '${income
              ? '+'
              : transfer
              ? ''
              : '−'}${money(entry.amountMinor, entry.currency)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: entry.kind == EntryKind.expense
                ? FinanceColors.of(context).expense
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      onTap: onTap ?? () => showEntryEditor(context, entry: entry),
    );
    if (!swipe) {
      return tile;
    }
    return Dismissible(
      key: ValueKey(entry.id),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.edit_outlined),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await showEntryEditor(context, entry: entry);
          return false;
        }
        try {
          await c.deleteEntry(entry.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Операция удалена'),
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'Отменить',
                  onPressed: () async {
                    try {
                      await c.saveEntry(entry);
                    } catch (e) {
                      if (context.mounted) {
                        showError(context, e);
                      }
                    }
                  },
                ),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            showError(context, e);
          }
        }
        return false;
      },
      child: tile,
    );
  }
}
