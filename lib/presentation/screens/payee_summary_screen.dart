import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/payee_summary.dart';
import '../../domain/service_catalog.dart';
import '../controller.dart';
import '../widgets/common.dart';
import '../widgets/entry_tile.dart';
import '../widgets/service_badge.dart';
import 'entry_editor.dart';

enum PayeePeriod { week, month, quarter, year, all, custom }

/// Spending with one payee (e.g. every «Whoosh» ride) over a chosen period.
/// Opened from the dashboard's recent operations; the tapped operation can
/// still be edited from the app bar.
class PayeeSummaryScreen extends StatefulWidget {
  const PayeeSummaryScreen({super.key, required this.entry});
  final FinanceEntry entry;
  @override
  State<PayeeSummaryScreen> createState() => _PayeeSummaryScreenState();
}

class _PayeeSummaryScreenState extends State<PayeeSummaryScreen> {
  PayeePeriod _period = PayeePeriod.month;
  DateTimeRange? _custom;

  static const _labels = {
    PayeePeriod.week: '7 дней',
    PayeePeriod.month: 'Месяц',
    PayeePeriod.quarter: '3 месяца',
    PayeePeriod.year: 'Год',
    PayeePeriod.all: 'Всё время',
    PayeePeriod.custom: 'Свой период',
  };

  (DateTime, DateTime) _range(FinanceController c) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return switch (_period) {
      PayeePeriod.week => (
        DateTime(now.year, now.month, now.day - 6),
        tomorrow,
      ),
      PayeePeriod.month => (c.periodStart, c.periodEnd),
      PayeePeriod.quarter => (
        DateTime(
          c.periodStart.year,
          c.periodStart.month - 2,
          c.periodStart.day,
        ),
        c.periodEnd,
      ),
      PayeePeriod.year => (
        DateTime(now.year - 1, now.month, now.day + 1),
        tomorrow,
      ),
      PayeePeriod.all => (
        PayeeSummary.firstDate(
              c.data.entries,
              widget.entry.payee,
              widget.entry.kind,
            ) ??
            DateTime(now.year, now.month, now.day),
        tomorrow,
      ),
      PayeePeriod.custom => (
        _custom!.start,
        DateTime(_custom!.end.year, _custom!.end.month, _custom!.end.day + 1),
      ),
    };
  }

  Future<void> _choose(PayeePeriod period) async {
    if (period != PayeePeriod.custom) {
      setState(() => _period = period);
      return;
    }
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange:
          _custom ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month, now.day),
          ),
    );
    if (picked != null && mounted) {
      setState(() {
        _custom = picked;
        _period = PayeePeriod.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final entry = widget.entry;
    final (start, end) = _range(c);
    final summary = PayeeSummary.compute(
      entries: c.data.entries,
      payee: entry.payee,
      kind: entry.kind,
      start: start,
      end: end,
    );
    final currencies = summary.totals.keys.toList()
      ..sort(
        (a, b) => a == c.currency ? -1 : (b == c.currency ? 1 : a.compareTo(b)),
      );
    final main = currencies.isEmpty ? entry.currency : currencies.first;
    final income = entry.kind == EntryKind.income;
    final colors = FinanceColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tone = income ? colors.income : colors.expense;
    final date = DateFormat('d MMM yyyy', 'ru');
    final service =
        ServiceCatalog.byId(entry.serviceId) ??
        ServiceCatalog.byName(entry.payee);
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.payee, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('payee-edit-entry'),
            tooltip: 'Изменить эту операцию',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showEntryEditor(context, entry: entry),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('payee-summary'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Container(
            key: const ValueKey('payee-hero'),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(tone.withValues(alpha: .28), scheme.surface),
                  Color.alphaBlend(
                    scheme.primary.withValues(alpha: .10),
                    scheme.surface,
                  ),
                ],
              ),
              border: Border.all(color: tone.withValues(alpha: .35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (service != null || entry.serviceIconPath != null)
                      ServiceBadge(
                        serviceId: entry.serviceId,
                        customIconPath: entry.serviceIconPath,
                        name: entry.payee,
                        size: 40,
                      )
                    else
                      CategoryBadge(
                        category: c.category(entry.categoryId),
                        size: 40,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        income
                            ? 'Поступления · ${_labels[_period]!.toLowerCase()}'
                            : 'Расходы · ${_labels[_period]!.toLowerCase()}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    money(summary.totals[main] ?? 0, main),
                    key: const ValueKey('payee-total'),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                for (final other in currencies.skip(1))
                  Text(
                    '+ ${money(summary.totals[other]!, other)}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${date.format(start)} — ${date.format(end.subtract(const Duration(days: 1)))}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in PayeePeriod.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('payee-period-${p.name}'),
                      label: Text(_labels[p]!),
                      selected: _period == p,
                      onSelected: (_) => _choose(p),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  title: 'Операций',
                  value: '${summary.count}',
                  valueKey: 'payee-count',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  title: 'В среднем',
                  value: money(summary.average(main), main),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  title: 'Последняя',
                  value: summary.entries.isEmpty
                      ? '—'
                      : DateFormat(
                          'd MMM',
                          'ru',
                        ).format(summary.entries.first.date),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: _Bars(
              buckets: summary.buckets(main),
              currency: main,
              color: tone,
              daily: end.difference(start).inDays <= 31,
            ),
          ),
          const SectionTitle('Операции за период'),
          if (summary.entries.isEmpty)
            const SurfaceCard(
              child: EmptyState(
                'Операций нет',
                'Выберите другой период.',
                icon: Icons.event_busy_outlined,
              ),
            )
          else
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (final e in summary.entries.take(200))
                    EntryTile(e, swipe: false),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.title, required this.value, this.valueKey});
  final String title, value;
  final String? valueKey;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            key: valueKey == null ? null : ValueKey<String>(valueKey!),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _Bars extends StatelessWidget {
  const _Bars({
    required this.buckets,
    required this.currency,
    required this.color,
    required this.daily,
  });
  final List<PayeeBucket> buckets;
  final String currency;
  final Color color;
  final bool daily;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = buckets.fold<int>(0, (m, b) => b.minor > m ? b.minor : m);
    final label = DateFormat(daily ? 'd' : 'LLL', 'ru');
    final step = buckets.length > 12 ? (buckets.length / 8).ceil() : 1;
    return Semantics(
      label:
          'Столбики по ${daily ? 'дням' : 'месяцам'}, максимум ${money(max, currency)}',
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < buckets.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: buckets.length > 16 ? 1 : 3,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: max == 0
                              ? .02
                              : (buckets[i].minor / max).clamp(.02, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: buckets[i].minor == 0
                                    ? [
                                        scheme.outlineVariant.withValues(
                                          alpha: .3,
                                        ),
                                        scheme.outlineVariant.withValues(
                                          alpha: .3,
                                        ),
                                      ]
                                    : [color.withValues(alpha: .55), color],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 14,
                        child: i % step == 0
                            ? FittedBox(
                                child: Text(
                                  label.format(buckets[i].start),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
