import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../presentation/controller.dart';
import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/widgets/common.dart';
import '../../../presentation/widgets/finora_orb.dart';
import '../models/ai_models.dart';
import '../responses/response_layer.dart';
import '../services/finora_ai.dart';
import '../services/finora_ai_snapshot.dart';
import '../widgets/insight_card.dart';

/// Finora AI: the forecast, insights and suggestions computed by the
/// engines, and a place to ask. Everything shown is calculated from the
/// person's own data; the words are templates over those numbers.
class FinoraAiScreen extends StatefulWidget {
  const FinoraAiScreen({super.key});
  @override
  State<FinoraAiScreen> createState() => _FinoraAiScreenState();
}

class _FinoraAiScreenState extends State<FinoraAiScreen> {
  final _ai = FinoraAi.instance;
  final _question = TextEditingController();
  final _answers = <AiAnswer>[];
  late final Future<void> _ready = _ai.ready();
  Object? _dataSeen;
  FinoraAiSnapshot? _snapshot;

  static const _quick = [
    'Почему трачу больше?',
    'Прогноз до конца месяца',
    'Сколько останется?',
    'Мои подписки',
    'Уложусь в бюджеты?',
    'Предложи бюджет',
  ];

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  FinoraAiSnapshot _snap(FinanceController c) {
    if (!identical(_dataSeen, c.data) || _snapshot == null) {
      _dataSeen = c.data;
      _snapshot = _ai.snapshot(c.data);
    }
    return _snapshot!;
  }

  void _ask(String q, FinoraAiSnapshot s) {
    final text = q.trim();
    if (text.isEmpty) return;
    setState(() {
      _answers.insert(0, _ai.answer(text, s));
      _question.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Финора · Анализ')),
      body: FutureBuilder<void>(
        future: _ready,
        builder: (context, done) {
          if (done.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = _snap(c);
          return ListView(
            key: const ValueKey('finora-ai'),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _head(s),
              const SizedBox(height: 16),
              _forecast(s),
              const SizedBox(height: 22),
              _askBox(s),
              for (final a in _answers) _answer(a, s),
              const SizedBox(height: 22),
              _insights(s),
              if (s.subscriptions.isNotEmpty) ...[
                const SizedBox(height: 22),
                _subscriptions(s),
              ],
              const SizedBox(height: 18),
              Text(
                'Все цифры посчитаны по вашим операциям прямо на телефоне — '
                'ничего не отправляется в интернет.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _head(FinoraAiSnapshot s) {
    final first = s.insights.firstOrNull;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const FinoraCharacter(size: 56, moods: [FinoraMood.happy]),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            first == null
                ? ResponseLayer.notEnough
                : ResponseLayer.insight(s, first),
            key: const ValueKey('finora-ai-headline'),
            style: const TextStyle(
              fontSize: 16,
              height: 1.3,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _forecast(FinoraAiSnapshot s) {
    final f = s.forecast;
    final scheme = Theme.of(context).colorScheme;
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
    return SurfaceCard(
      key: const ValueKey('finora-ai-forecast'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Прогноз на месяц',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          if (f.insufficient != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                ResponseLayer.needHistory,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else ...[
            line('Расходы к концу месяца', f.projectedExpense, strong: true),
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
    );
  }

  Widget _askBox(FinoraAiSnapshot s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Спросить Финору', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      TextField(
        key: const ValueKey('finora-ai-question'),
        controller: _question,
        textInputAction: TextInputAction.send,
        onSubmitted: (q) => _ask(q, s),
        decoration: InputDecoration(
          hintText: 'Например: почему я трачу больше?',
          suffixIcon: IconButton(
            key: const ValueKey('finora-ai-send'),
            icon: const Icon(Icons.arrow_upward_rounded),
            onPressed: () => _ask(_question.text, s),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final q in _quick)
            ActionChip(label: Text(q), onPressed: () => _ask(q, s)),
        ],
      ),
    ],
  );

  Widget _answer(AiAnswer a, FinoraAiSnapshot s) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: SurfaceCard(
      key: ValueKey('finora-ai-answer-${_answers.indexOf(a)}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FinoraCharacter(size: 30, moods: [FinoraMood.happy]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              a.text,
              style: const TextStyle(fontSize: 15, height: 1.32),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _insights(FinoraAiSnapshot s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Что я заметила', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      SurfaceCard(
        key: const ValueKey('finora-ai-insights'),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Column(
          children: [
            for (final i in s.insights.skip(1).take(10))
              InsightTile(kind: i.kind, text: ResponseLayer.insight(s, i)),
            if (s.insights.length <= 1)
              const InsightTile(
                kind: InsightKind.notEnoughData,
                text:
                    'Пока больше нечего рассказать — добавьте операции, и '
                    'я начну находить закономерности.',
              ),
          ],
        ),
      ),
    ],
  );

  Widget _subscriptions(FinoraAiSnapshot s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Похоже на подписки',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 6),
      for (final sub in s.subscriptions)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SurfaceCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
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
                      onPressed: () => setState(() {
                        _ai.rejectSubscription(sub);
                        _snapshot = null;
                      }),
                      child: const Text('Нет'),
                    ),
                    TextButton(
                      key: ValueKey('ai-sub-yes-${sub.merchantKey}'),
                      onPressed: () => setState(() {
                        _ai.confirmSubscription(sub);
                        _snapshot = null;
                      }),
                      child: const Text('Да, подписка'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
