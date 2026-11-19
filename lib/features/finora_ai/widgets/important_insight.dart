import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../domain/models.dart';
import '../../../presentation/controller.dart';
import '../../../presentation/l10n_widgets.dart';
import '../models/ai_models.dart';
import '../responses/response_layer.dart';
import '../services/finora_ai.dart';
import '../services/finora_ai_snapshot.dart';

/// The home screen's priority (Phase 6): when Finora AI sees something that
/// needs attention now — money may run short, a budget is about to be
/// exceeded, a payment is late, an unusual expense — it comes first, above
/// the blocks the person arranged. «Понятно» puts it aside for three days.
/// Nothing is shown when insights are turned off or all is calm.
class ImportantInsightCard extends StatefulWidget {
  const ImportantInsightCard({super.key});

  /// The insight to raise, if any: the top warning not put aside.
  static Insight? pick(FinoraAiSnapshot s, DateTime now) => s.top
      .where(
        (i) =>
            i.severity == InsightSeverity.warning &&
            !(s.memory?.isSnoozed(i.dedupKey, now) ?? false),
      )
      .firstOrNull;

  @override
  State<ImportantInsightCard> createState() => _ImportantInsightCardState();
}

class _ImportantInsightCardState extends State<ImportantInsightCard> {
  FinanceData? _seen;
  FinoraAiSnapshot? _snapshot;

  FinoraAiSnapshot _snap(FinanceData data) {
    if (!identical(data, _seen) || _snapshot == null) {
      _seen = data;
      _snapshot = FinoraAi.instance.snapshot(data);
    }
    return _snapshot!;
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final ai = c.data.preferences.ai;
    if (!ai.enabled || !ai.insights || c.data.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final s = _snap(c.data);
    final insight = ImportantInsightCard.pick(s, DateTime.now());
    if (insight == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    const tone = Color(0xFFE8803A);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        key: const ValueKey('important-insight'),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: tone.withValues(alpha: .35)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: tone,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ResponseLayer.insight(s, insight),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey('important-insight-ok'),
                  onPressed: () {
                    final ai = FinoraAi.instance;
                    ai.memory.snooze(insight.dedupKey, days: 3);
                    ai.memoryRepository.saveSoon();
                    setState(() => _snapshot = null);
                  },
                  child: const Text('Понятно'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
