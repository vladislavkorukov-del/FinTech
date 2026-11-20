import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:share_plus/share_plus.dart';

import '../../../presentation/controller.dart';
import '../../../presentation/l10n_widgets.dart';
import '../reports/report_builder.dart';

/// «Отчёт» (Phase 7): the week or month in numbers, counted from the
/// operations, ready to read or share. The current period so far, or the
/// previous one in full.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  ReportPeriod _period = ReportPeriod.month;
  bool _previous = false;

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final report = ReportBuilder.build(
      c.data,
      period: _period,
      previous: _previous,
    );
    final text = ReportBuilder.text(report);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчёт'),
        actions: [
          IconButton(
            key: const ValueKey('report-share'),
            tooltip: 'Поделиться',
            onPressed: () => SharePlus.instance.share(ShareParams(text: text)),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SegmentedButton<ReportPeriod>(
            segments: const [
              ButtonSegment(value: ReportPeriod.week, label: Text('Неделя')),
              ButtonSegment(value: ReportPeriod.month, label: Text('Месяц')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            key: const ValueKey('report-previous'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              _period == ReportPeriod.week ? 'Прошлая неделя' : 'Прошлый месяц',
            ),
            value: _previous,
            onChanged: (v) => setState(() => _previous = v),
          ),
          const SizedBox(height: 8),
          SelectableText(
            text,
            key: const ValueKey('report-text'),
            style: const TextStyle(fontSize: 15.5, height: 1.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Спросите Финору: «отчёт за прошлую неделю», «дайджест за месяц».',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
