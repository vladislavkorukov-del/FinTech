import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/widgets/common.dart';
import '../models/ai_models.dart';
import '../responses/response_layer.dart';
import '../services/ai_context.dart';
import '../services/finora_ai.dart';
import '../services/finora_ai_snapshot.dart';
import '../widgets/ai_chat_widgets.dart';
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
    // Finora AI's buttons stay orange whatever the app theme.
    builder: (context, scroll) => Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(
          context,
        ).colorScheme.copyWith(primary: AiLook.orange, onPrimary: Colors.white),
      ),
      child: _Analysis(snapshot: s, scroll: scroll, onChanged: onChanged),
    ),
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
        // «Умные наблюдения» can be turned off in the AI settings.
        if (s.ctx.data.preferences.ai.insights) ...[
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
        ],
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
        // Phase 3: payments ahead, subscriptions, savings and stability,
        // dreams — each only when there is something to show.
        if (s.timeline.events.isNotEmpty || s.timeline.late.isNotEmpty) ...[
          title('Ближайшие платежи'),
          SurfaceCard(
            key: const ValueKey('finora-ai-upcoming'),
            child: Text(ResponseLayer.upcoming(s)),
          ),
        ],
        if (ResponseLayer.subscriptionSummary(s).isNotEmpty) ...[
          title('Подписки'),
          SurfaceCard(
            key: const ValueKey('finora-ai-subscriptions'),
            child: Text(ResponseLayer.subscriptionSummary(s)),
          ),
        ],
        if (s.cushion != null || s.stability != null) ...[
          title('Подушка и стабильность'),
          SurfaceCard(
            key: const ValueKey('finora-ai-health'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (s.cushion != null) Text(ResponseLayer.cushion(s)),
                if (s.cushion != null && s.stability != null)
                  const SizedBox(height: 10),
                if (s.stability != null) Text(ResponseLayer.stability(s)),
              ],
            ),
          ),
        ],
        if (s.goalForecasts.any((g) => !g.done)) ...[
          title('Мечты'),
          SurfaceCard(
            key: const ValueKey('finora-ai-goals'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final g in s.goalForecasts.where((g) => !g.done))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      ResponseLayer.insight(
                        s,
                        Insight(
                          kind: InsightKind.goal,
                          priority: 0,
                          subject: g.goal.name,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        // An unusual month: should forecasts count it?
        for (final i in s.insights.where(
          (i) =>
              i.kind == InsightKind.unusualMonth &&
              !_answered.contains('month:${i.subject}'),
        )) ...[
          title('Необычный месяц'),
          SurfaceCard(
            key: const ValueKey('finora-ai-unusual'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ResponseLayer.insight(s, i)),
                const SizedBox(height: 6),
                const Text('Учитывать его в будущих прогнозах как обычный?'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const ValueKey('ai-month-exclude'),
                      onPressed: () {
                        FinoraAi.instance.excludeMonth(
                          AiContext.monthKey(DateTime.parse(i.subject!)),
                        );
                        setState(() => _answered.add('month:${i.subject}'));
                        widget.onChanged();
                      },
                      child: const Text('Нет'),
                    ),
                    TextButton(
                      key: const ValueKey('ai-month-keep'),
                      onPressed: () {
                        FinoraAi.instance.keepMonth(
                          AiContext.monthKey(DateTime.parse(i.subject!)),
                        );
                        setState(() => _answered.add('month:${i.subject}'));
                        widget.onChanged();
                      },
                      child: const Text('Да, обычный'),
                    ),
                  ],
                ),
              ],
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
