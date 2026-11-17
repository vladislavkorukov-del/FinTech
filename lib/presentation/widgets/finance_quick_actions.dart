import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide InputDecoration, Text;
import '../../domain/models.dart';
import '../screens/entry_editor.dart';
import '../l10n_widgets.dart';

class FinanceQuickActions extends StatelessWidget {
  const FinanceQuickActions({super.key});
  @override
  Widget build(BuildContext context) {
    final stacked =
        MediaQuery.textScalerOf(context).scale(1) > 1.2 ||
        MediaQuery.sizeOf(context).width < 330;
    const actions = [
      (EntryKind.income, 'Доход', CupertinoIcons.plus),
      (EntryKind.expense, 'Расход', CupertinoIcons.minus),
      (EntryKind.transfer, 'Перевод', CupertinoIcons.arrow_right_arrow_left),
    ];
    // iOS-strict: neutral buttons, one tint colour for the symbols.
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Color tone(EntryKind kind) => scheme.primary;
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
                backgroundColor: scheme.surface.withValues(
                  alpha: dark ? .55 : 1,
                ),
                foregroundColor: scheme.onSurface,
                shape: const RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
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
