import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../domain/finance_engine.dart';
import '../../domain/models.dart';
import 'common.dart';
import '../l10n_widgets.dart';

/// 1.37: «Откладывайте: 340 ₽ в день · 2 400 ₽ в неделю · 10 300 ₽ в месяц»
/// to reach a dream by its date.
class SavingsPace extends StatelessWidget {
  const SavingsPace({
    super.key,
    required this.goal,
    required this.saved,
    this.compact = false,
  });
  final Goal goal;
  final int saved;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pace = FinanceEngine.savingsPace(goal, saved);
    if (pace == null) {
      if (goal.deadline != null || saved >= goal.targetMinor) {
        return const SizedBox.shrink();
      }
      return Text(
        'Укажите дату — Финора посчитает, сколько откладывать',
        key: ValueKey('pace-${goal.id}'),
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      );
    }
    if (pace.days <= 0) {
      return Text(
        'Срок прошёл — не хватает ${money(pace.left, goal.currency)}',
        key: ValueKey('pace-${goal.id}'),
        style: TextStyle(fontSize: 12, color: scheme.error),
      );
    }
    String m(int v) => money(v, goal.currency);
    final cells = [
      (m(pace.day), 'в день'),
      if (pace.days >= 7) (m(pace.week), 'в неделю'),
      if (pace.days >= 30) (m(pace.month), 'в месяц'),
    ];
    return Container(
      key: ValueKey('pace-${goal.id}'),
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Откладывайте, чтобы успеть за ${pace.days} дн.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final (value, unit) in cells)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: compact ? 13 : 15,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      Text(
                        unit,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
