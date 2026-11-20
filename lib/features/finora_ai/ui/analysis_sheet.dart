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
/// the engines' results as a plain list, readable without the chat. Drawn
/// in Finora AI's own look: deep ember, glass panels, orange accents.
Future<void> showAnalysisSheet(
  BuildContext context,
  FinoraAiSnapshot s, {
  required VoidCallback onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (context) {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final theme = base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: AiLook.orange,
        onPrimary: Colors.white,
        surface: const Color(0xFF140C08),
        onSurface: Colors.white,
        onSurfaceVariant: AiLook.soft(.62),
        outlineVariant: AiLook.soft(.14),
      ),
      textTheme: Theme.of(context).textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
        fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AiLook.orange),
      ),
      dividerColor: AiLook.soft(.1),
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .88,
      maxChildSize: .95,
      builder: (context, scroll) => Theme(
        data: theme,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: DecoratedBox(
            key: const ValueKey('finora-ai-analysis'),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .35, 1],
                colors: [
                  Color(0xFF3A1508),
                  Color(0xFF1A0C07),
                  Color(0xFF0B0807),
                ],
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AiLook.soft(.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: _Analysis(
                    snapshot: s,
                    scroll: scroll,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  },
);

/// A glass panel of the analysis (in place of the app's light cards).
class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AiLook.soft(.06),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AiLook.soft(.1), width: .8),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white, height: 1.38),
      child: child,
    ),
  );
}

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
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              gradient: AiLook.accent(),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            t,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
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
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AiLook.accent(),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Анализ',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -.3,
                ),
              ),
            ],
          ),
        ),
        title('Прогноз на месяц'),
        _Panel(
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
          _Panel(
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
              child: _Panel(
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
          _Panel(
            key: const ValueKey('finora-ai-upcoming'),
            child: Text(ResponseLayer.upcoming(s)),
          ),
        ],
        if (ResponseLayer.subscriptionSummary(s).isNotEmpty) ...[
          title('Подписки'),
          _Panel(
            key: const ValueKey('finora-ai-subscriptions'),
            child: Text(ResponseLayer.subscriptionSummary(s)),
          ),
        ],
        if (s.cushion != null || s.stability != null) ...[
          title('Подушка и стабильность'),
          _Panel(
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
          _Panel(
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
          _Panel(
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
