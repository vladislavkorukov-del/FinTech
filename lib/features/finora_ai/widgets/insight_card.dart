import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../presentation/l10n_widgets.dart';
import '../models/ai_models.dart';

/// One insight: a line symbol in the accent and Finora's sentence.
class InsightTile extends StatelessWidget {
  const InsightTile({super.key, required this.kind, required this.text});
  final InsightKind kind;
  final String text;

  static IconData iconFor(InsightKind k) => switch (k) {
    InsightKind.summary => CupertinoIcons.doc_text,
    InsightKind.growth => CupertinoIcons.arrow_up_right,
    InsightKind.decrease => CupertinoIcons.arrow_down_right,
    InsightKind.forecast => CupertinoIcons.graph_square,
    InsightKind.freeMoney => CupertinoIcons.money_rubl_circle,
    InsightKind.subscription => CupertinoIcons.arrow_2_circlepath,
    InsightKind.recurring => CupertinoIcons.arrow_2_circlepath,
    InsightKind.anomaly => CupertinoIcons.exclamationmark_circle,
    InsightKind.budgetRisk => CupertinoIcons.gauge,
    InsightKind.trend => CupertinoIcons.chart_bar_alt_fill,
    InsightKind.incomeStability => CupertinoIcons.waveform_path_ecg,
    InsightKind.habit => CupertinoIcons.calendar,
    InsightKind.unusualMonth => CupertinoIcons.flag,
    InsightKind.suggestion => CupertinoIcons.lightbulb,
    InsightKind.goal => CupertinoIcons.star,
    InsightKind.notEnoughData => CupertinoIcons.hourglass,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconFor(kind), size: 22, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, height: 1.32),
            ),
          ),
        ],
      ),
    );
  }
}
