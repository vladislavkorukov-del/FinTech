import 'dart:async';

import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:intl/intl.dart';

import '../../domain/finance_engine.dart';
import '../../domain/models.dart';
import '../controller.dart';
import '../widgets/common.dart';
import '../widgets/charts.dart';
import '../widgets/category_orbit_chart.dart';
import '../widgets/half_year_chart.dart';
import 'transactions.dart';
import '../l10n_widgets.dart';
import '../i18n.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _period = 'Месяц';
  EntryKind _kind = EntryKind.expense;
  DateTimeRange? _custom;
  String? _currency;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _seen());
  }

  /// 1.44: a period looked at counts for «Аналитик».
  void _seen() {
    if (!mounted) return;
    final c = FinanceScope.of(context);
    final (start, _) = range(c);
    unawaited(
      c.noteAnalytics('$_period:${start.toIso8601String().substring(0, 10)}'),
    );
  }

  (DateTime, DateTime) range(FinanceController c) {
    final n = DateUtils.dateOnly(DateTime.now());
    return switch (_period) {
      'День' => (n, DateTime(n.year, n.month, n.day + 1)),
      'Неделя' => (
        DateTime(
          n.year,
          n.month,
          n.day - (n.weekday - c.data.preferences.weekStart + 7) % 7,
        ),
        DateTime(
          n.year,
          n.month,
          n.day - (n.weekday - c.data.preferences.weekStart + 7) % 7 + 7,
        ),
      ),
      'Квартал' => (
        DateTime(n.year, ((n.month - 1) ~/ 3) * 3 + 1),
        DateTime(n.year, ((n.month - 1) ~/ 3) * 3 + 4),
      ),
      'Год' => (DateTime(n.year), DateTime(n.year + 1)),
      'Период' =>
        _custom == null
            ? (c.periodStart, c.periodEnd)
            : (
                _custom!.start,
                DateTime(
                  _custom!.end.year,
                  _custom!.end.month,
                  _custom!.end.day + 1,
                ),
              ),
      _ => (c.periodStart, c.periodEnd),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (start, end) = range(c);
    final currency = _currency ?? c.currency;
    final totals = FinanceEngine.totals(c.data.entries, start, end, currency);
    final cats = FinanceEngine.categoryTotals(
      c.data.entries,
      start,
      end,
      currency,
      _kind,
    ).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final days = DateTime.utc(
      end.year,
      end.month,
      end.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
    final buckets = days.clamp(1, 31).toInt();
    final daily = <int, int>{};
    for (final e in c.data.entries) {
      if (e.kind != EntryKind.expense ||
          e.status != 'posted' ||
          e.currency != currency ||
          e.date.isBefore(start) ||
          !e.date.isBefore(end)) {
        continue;
      }
      final local = e.date.toLocal();
      final index = DateTime.utc(
        local.year,
        local.month,
        local.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
      if (index >= 0 && index < days) {
        daily[index] = (daily[index] ?? 0) + e.amountMinor;
      }
    }
    final balance = List.generate(buckets, (i) {
      final date = DateTime(
        start.year,
        start.month,
        start.day + (days * (i + 1) / buckets).floor(),
      );
      return FinanceEngine.totalBalance(
            c.data.accounts,
            c.data.entries.where((e) => e.date.isBefore(date)).toList(),
            currency,
            c.data.goals,
          ) /
          100;
    });
    final monthly = List.generate(6, (i) {
      final s = DateTime(DateTime.now().year, DateTime.now().month - 5 + i);
      return FinanceEngine.totals(
        c.data.entries,
        s,
        DateTime(s.year, s.month + 1),
        currency,
      );
    });
    void open(String category) => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TransactionsScreen(
          categoryId: category,
          initialRange: DateTimeRange(
            start: start,
            end: DateTime(end.year, end.month, end.day - 1),
          ),
        ),
      ),
    );
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        // Apple polish: a large title on the main tab.
        toolbarHeight: Navigator.canPop(context) ? null : 64,
        titleSpacing: Navigator.canPop(context) ? null : 20,
        titleTextStyle: Navigator.canPop(context)
            ? null
            : Theme.of(context).textTheme.headlineLarge,
        title: const Text('Аналитика'),
        actions: [
          DropdownButton<String>(
            value: currency,
            underline: const SizedBox.shrink(),
            items: {
              ...currencies,
              currency,
              ...c.data.accounts.map((a) => a.currency),
            }.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => _currency = v),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['День', 'Неделя', 'Месяц', 'Квартал', 'Год', 'Период']
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p),
                        selected: _period == p,
                        onSelected: (_) async {
                          if (p == 'Период') {
                            final r = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(1900),
                              lastDate: DateTime(2200, 12, 31),
                              initialDateRange: _custom,
                            );
                            if (r == null) {
                              return;
                            }
                            if (mounted) {
                              setState(() {
                                _custom = r;
                                _period = p;
                              });
                              _seen();
                            }
                          } else {
                            setState(() => _period = p);
                            _seen();
                          }
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '${DateFormat('d MMM yyyy', AppLanguage.intl).format(start)} — ${DateFormat('d MMM yyyy', AppLanguage.intl).format(DateTime(end.year, end.month, end.day - 1))}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          SegmentedButton<EntryKind>(
            segments: const [
              ButtonSegment(value: EntryKind.expense, label: Text('Расходы')),
              ButtonSegment(value: EntryKind.income, label: Text('Доходы')),
            ],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() => _kind = v.first),
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            padding: const EdgeInsets.all(14),
            child: CategoryOrbitChart(
              kind: _kind,
              slices: cats.map((item) {
                final category = c.category(item.key);
                return CategorySlice(
                  id: item.key,
                  name: category?.name ?? 'Прочее',
                  icon: categoryIcon(category?.icon ?? 19),
                  color: Color(
                    category?.color ??
                        categoryColors[item.key.hashCode.abs() %
                            categoryColors.length],
                  ),
                  amount: item.value,
                );
              }).toList(),
              currency: currency,
              onDetails: open,
            ),
          ),
          const SectionTitle('Доходы и расходы'),
          SurfaceCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        'Доходы',
                        money(totals.income, currency),
                        FinanceColors.of(context).income,
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        'Расходы',
                        money(totals.expense, currency),
                        FinanceColors.of(context).expense,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _Comparison(income: totals.income, expense: totals.expense),
                const SizedBox(height: 14),
                Text(
                  'Разница: ${money(totals.net, currency)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SectionTitle('Ежедневные расходы'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Сумма над каждым днём · листайте по горизонтали',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                DailyExpenseChart(
                  start: start,
                  days: days,
                  amountsMinor: daily,
                  currency: currency,
                  focusDay: DateUtils.dateOnly(
                    DateTime.now(),
                  ).difference(start).inDays.clamp(0, days - 1),
                  onDayTap: (date) => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => TransactionsScreen(
                        initialRange: DateTimeRange(start: date, end: date),
                        initialKind: EntryKind.expense,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('Изменение баланса'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Активные счета · $currency',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                TrendChart(values: balance, color: scheme.primary),
              ],
            ),
          ),
          const SectionTitle('Последние 6 месяцев'),
          SurfaceCard(
            child: HalfYearChart(
              months: List.generate(
                6,
                (i) => MonthFlow(
                  month: DateTime(
                    DateTime.now().year,
                    DateTime.now().month - 5 + i,
                  ),
                  income: monthly[i].income,
                  expense: monthly[i].expense,
                ),
              ),
              currency: currency,
            ),
          ),
          if (c.data.goals.isNotEmpty) ...[
            const SectionTitle('Накопления по целям'),
            ...c.data.goals
                .where((g) => g.currency == currency)
                .map(
                  (g) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.name),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value:
                                (FinanceEngine.goalSaved(g, c.data.entries) /
                                        g.targetMinor)
                                    .clamp(0, 1),
                            color: scheme.primary,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${money(FinanceEngine.goalSaved(g, c.data.entries), g.currency)} из ${money(g.targetMinor, g.currency)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.title, this.value, this.color);
  final String title, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: TextStyle(color: color, fontSize: 12)),
      const SizedBox(height: 8),
      FittedBox(
        child: Text(value, style: Theme.of(context).textTheme.titleLarge),
      ),
    ],
  );
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.income, required this.expense});
  final int income, expense;
  @override
  Widget build(BuildContext context) {
    final total = income + expense;
    return Column(
      children: [
        LinearProgressIndicator(
          value: total == 0 ? 0 : income / total,
          color: FinanceColors.of(context).income,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .12),
          minHeight: 7,
          borderRadius: BorderRadius.circular(7),
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: total == 0 ? 0 : expense / total,
          color: FinanceColors.of(context).expense,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .12),
          minHeight: 7,
          borderRadius: BorderRadius.circular(7),
        ),
      ],
    );
  }
}
