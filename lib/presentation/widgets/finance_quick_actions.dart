import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../screens/entry_editor.dart';
import 'common.dart';

class FinanceQuickActions extends StatelessWidget {
  const FinanceQuickActions({super.key});
  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    final stacked =
        MediaQuery.textScalerOf(context).scale(1) > 1.2 ||
        MediaQuery.sizeOf(context).width < 330;
    const actions = [
      (EntryKind.income, 'Доход', Icons.add_rounded),
      (EntryKind.expense, 'Расход', Icons.remove_rounded),
      (EntryKind.transfer, 'Перевод', Icons.swap_horiz_rounded),
    ];
    // 1.16: three equal, quiet buttons; only the icon carries a color.
    final scheme = Theme.of(context).colorScheme;
    Color tone(EntryKind kind) => switch (kind) {
      EntryKind.income => colors.income,
      EntryKind.expense => colors.expense,
      EntryKind.transfer => scheme.onSurfaceVariant,
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
                backgroundColor: GlassSurface.pane(
                  Theme.of(context),
                  null,
                  null,
                  1,
                ),
                side: BorderSide(
                  color: scheme.onSurface.withValues(alpha: .07),
                ),
                foregroundColor: scheme.onSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
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
                            fontSize: 12,
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
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
        // 1.19: voice entry — say «Пятёрочка 450 рублей».
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton.outlined(
            key: const ValueKey('quick-action-voice'),
            tooltip: 'Голосом',
            style: IconButton.styleFrom(
              backgroundColor: GlassSurface.pane(
                Theme.of(context),
                null,
                null,
                1,
              ),
              foregroundColor: scheme.onSurface,
              side: BorderSide(color: scheme.onSurface.withValues(alpha: .07)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            onPressed: () => showEntryEditor(context, startVoice: true),
            icon: const Icon(Icons.mic_none_rounded, size: 20),
          ),
        ),
      ],
    );
  }
}
