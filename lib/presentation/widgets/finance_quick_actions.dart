import 'package:flutter/material.dart' hide InputDecoration, Text;
import '../../domain/models.dart';
import '../screens/entry_editor.dart';
import 'grouped_list.dart';
import '../l10n_widgets.dart';

class FinanceQuickActions extends StatelessWidget {
  const FinanceQuickActions({super.key});
  @override
  Widget build(BuildContext context) {
    final stacked =
        MediaQuery.textScalerOf(context).scale(1) > 1.2 ||
        MediaQuery.sizeOf(context).width < 330;
    const actions = [
      (EntryKind.income, 'Доход', Icons.add_rounded),
      (EntryKind.expense, 'Расход', Icons.remove_rounded),
      (EntryKind.transfer, 'Перевод', Icons.swap_horiz_rounded),
    ];
    // Release: three bright tinted buttons — green income, red expense,
    // blue transfer.
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Color tone(EntryKind kind) => switch (kind) {
      EntryKind.income => TileColors.green,
      EntryKind.expense => TileColors.red,
      EntryKind.transfer => TileColors.blue,
    };
    return Row(
      key: const ValueKey('dashboard-actions'),
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonal(
              key: ValueKey('quick-action-${actions[i].$1.name}'),
              onPressed: () => showEntryEditor(context, kind: actions[i].$1),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                backgroundColor: Color.alphaBlend(
                  tone(actions[i].$1).withValues(alpha: dark ? .22 : .14),
                  scheme.surface,
                ),
                foregroundColor: scheme.onSurface,
                shape: const RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
              ),
              child: stacked
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          actions[i].$3,
                          size: 16,
                          color: tone(actions[i].$1),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          actions[i].$2,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          actions[i].$3,
                          size: 17,
                          color: tone(actions[i].$1),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            actions[i].$2,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ],
    );
  }
}
