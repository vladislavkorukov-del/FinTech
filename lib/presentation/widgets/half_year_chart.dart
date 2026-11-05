import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'common.dart';

class MonthFlow {
  const MonthFlow({
    required this.month,
    required this.income,
    required this.expense,
  });
  final DateTime month;
  final int income, expense;
}

class HalfYearChart extends StatefulWidget {
  const HalfYearChart({
    super.key,
    required this.months,
    required this.currency,
  });
  final List<MonthFlow> months;
  final String currency;
  @override
  State<HalfYearChart> createState() => _HalfYearChartState();
}

class _HalfYearChartState extends State<HalfYearChart> {
  int? _selected;
  Future<void> _show(int index) async {
    setState(() => _selected = index);
    final month = widget.months[index];
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              DateFormat('LLLL yyyy', 'ru').format(month.month),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            _flowRow(
              context,
              'Доходы',
              month.income,
              FinanceColors.of(context).income,
            ),
            _flowRow(
              context,
              'Расходы',
              month.expense,
              FinanceColors.of(context).expense,
            ),
            const Divider(),
            _flowRow(
              context,
              'Разница',
              month.income - month.expense,
              Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  Widget _flowRow(BuildContext context, String name, int amount, Color color) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(name)),
            Flexible(
              child: Text(
                money(amount, widget.currency),
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final maximum = widget.months.fold<int>(
      1,
      (sum, month) => math.max(sum, math.max(month.income, month.expense)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _legend('Доходы', colors.income),
            _legend('Расходы', colors.expense),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 178,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.months.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    label:
                        '${DateFormat('MMMM yyyy', 'ru').format(widget.months[i].month)}: доходы ${money(widget.months[i].income, widget.currency)}, расходы ${money(widget.months[i].expense, widget.currency)}',
                    child: InkWell(
                      key: ValueKey('month-flow-$i'),
                      onTap: () => _show(i),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _selected == i
                              ? scheme.primary.withValues(alpha: .1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _bar(
                                    widget.months[i].income / maximum * 122,
                                    colors.income,
                                  ),
                                  const SizedBox(width: 3),
                                  _bar(
                                    widget.months[i].expense / maximum * 122,
                                    colors.expense,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              DateFormat(
                                'MMM',
                                'ru',
                              ).format(widget.months[i].month),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bar(double height, Color color) => Flexible(
    child: Container(
      width: 13,
      height: math.max(2, height),
      decoration: BoxDecoration(
        color: height == 0 ? color.withValues(alpha: .2) : color,
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
  Widget _legend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 7),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}
