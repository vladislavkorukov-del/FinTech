import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/widgets/common.dart';
import '../models/ai_models.dart';
import '../responses/response_layer.dart';
import '../services/finora_ai.dart';
import '../services/finora_ai_snapshot.dart';
import '../widgets/insight_card.dart';

/// «Анализ»: the forecast, what Finora noticed and possible subscriptions —
/// the engines' results as a plain list, readable without the chat.
Future<void> showAnalysisSheet(
  BuildContext context,
  FinoraAiSnapshot s, {
  required VoidCallback onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .85,
    maxChildSize: .95,
    builder: (context, scroll) =>
        _Analysis(snapshot: s, scroll: scroll, onChanged: onChanged),
  ),
);

class _Analysis extends StatefulWidget {
  const _Analysis({
    required this.snapshot,
    required this.scroll,
    required this.onChanged,
  });
  final FinoraAiSnapshot snapshot;
  final ScrollController scroll;
  final VoidCallback onChanged;
  @override
  State<_Analysis> createState() => _AnalysisState();
}

class _AnalysisState extends State<_Analysis> {
  final _answered = <String>{};

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final scheme = Theme.of(context).colorScheme;
    final f = s.forecast;
    Widget title(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(t, style: Theme.of(context).textTheme.titleMedium),
    );
    Widget line(String label, int value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
            ),
          ),
          Text(
            money(value, s.ctx.currency),
            style: TextStyle(
              fontSize: strong ? 17 : 15,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    final subs = s.subscriptions
        .where((c) => !_answered.contains(c.merchantKey))
        .toList();
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Text('Анализ', style: Theme.of(context).textTheme.headlineSmall),
        title('Прогноз на месяц'),
        SurfaceCard(
          key: const ValueKey('finora-ai-forecast'),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Column(
            children: [
              if (f.insufficient != null)
                Text(
                  ResponseLayer.needHistory,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              else ...[
                line(
                  'Расходы к концу месяца',
                  f.projectedExpense,
                  strong: true,
                ),
                line('Доходы за месяц', f.projectedIncome),
                line('На счетах к концу месяца', f.projectedBalance),
              ],
              line('Обязательные платежи впереди', s.cashflow.mandatory),
              line(
                'Останется после обязательных',
                s.cashflow.afterMandatory,
                strong: true,
              ),
            ],
          ),
        ),
        title('Что я заметила'),
        SurfaceCard(
          key: const ValueKey('finora-ai-insights'),
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Column(
            children: [
              for (final i in s.insights.take(12))
                InsightTile(kind: i.kind, text: ResponseLayer.insight(s, i)),
            ],
          ),
        ),
        if (subs.isNotEmpty) ...[
          title('Похоже на подписки'),
          for (final sub in subs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ResponseLayer.insight(
                        s,
                        Insight(
                          kind: InsightKind.subscription,
                          priority: 0,
                          recurring: sub,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          key: ValueKey('ai-sub-no-${sub.merchantKey}'),
                          onPressed: () {
                            FinoraAi.instance.rejectSubscription(sub);
                            setState(() => _answered.add(sub.merchantKey));
                            widget.onChanged();
                          },
                          child: const Text('Нет'),
                        ),
                        TextButton(
                          key: ValueKey('ai-sub-yes-${sub.merchantKey}'),
                          onPressed: () {
                            FinoraAi.instance.confirmSubscription(sub);
                            setState(() => _answered.add(sub.merchantKey));
                            widget.onChanged();
                          },
                          child: const Text('Да, подписка'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 14),
        Text(
          'Все цифры посчитаны по вашим операциям прямо на телефоне — '
          'ничего не отправляется в интернет.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
