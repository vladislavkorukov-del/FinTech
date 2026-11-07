part of 'management.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime selected = DateUtils.dateOnly(DateTime.now());
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final month = DateTime(selected.year, selected.month);
    final total = DateTime(selected.year, selected.month + 1, 0).day;
    final offset = (month.weekday - c.data.preferences.weekStart) % 7;
    final entries =
        c.data.entries
            .where((e) => DateUtils.isSameDay(e.date.toLocal(), selected))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return Scaffold(
      appBar: AppBar(title: const Text('Календарь финансов')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SurfaceCard(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Прошлый месяц',
                      onPressed: () => setState(
                        () => selected = DateTime(
                          selected.year,
                          selected.month - 1,
                        ),
                      ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        DateFormat(
                          'LLLL yyyy',
                          AppLanguage.intl,
                        ).format(selected),
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Следующий месяц',
                      onPressed: () => setState(
                        () => selected = DateTime(
                          selected.year,
                          selected.month + 1,
                        ),
                      ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: List.generate(
                    7,
                    (i) => Expanded(
                      child: Text(
                        weekdays[(i + c.data.preferences.weekStart - 1) % 7],
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent:
                        78.0 * MediaQuery.textScalerOf(context).scale(1),
                  ),
                  itemCount: offset + total,
                  itemBuilder: (_, i) {
                    if (i < offset) {
                      return const SizedBox.shrink();
                    }
                    final day = i - offset + 1;
                    final date = DateTime(selected.year, selected.month, day);
                    final items = c.data.entries
                        .where(
                          (e) => DateUtils.isSameDay(e.date.toLocal(), date),
                        )
                        .toList();
                    final posted = items.where(
                      (e) => e.status == 'posted' && e.currency == c.currency,
                    );
                    final income = posted
                        .where((e) => e.kind == EntryKind.income)
                        .fold(0, (s, e) => s + e.amountMinor);
                    final expense = posted
                        .where((e) => e.kind == EntryKind.expense)
                        .fold(0, (s, e) => s + e.amountMinor);
                    final isSelected = day == selected.day;
                    return InkWell(
                      onTap: () => setState(() => selected = date),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: .14)
                              : null,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$day',
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                            if (items.isNotEmpty)
                              Text(
                                '${items.length} оп.',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 9),
                              ),
                            if (income > 0)
                              Text(
                                '+${NumberFormat.compact(locale: AppLanguage.intl).format(income / 100)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: FinanceColors.of(context).income,
                                ),
                              ),
                            if (expense > 0)
                              Text(
                                '−${NumberFormat.compact(locale: AppLanguage.intl).format(expense / 100)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: FinanceColors.of(context).expense,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          SectionTitle(DateFormat('d MMMM', AppLanguage.intl).format(selected)),
          Text(
            'Суммы календаря в ${c.currency}. Список ниже включает все валюты.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const EmptyState('Свободный день', 'За эту дату операций нет.'),
          ...entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SurfaceCard(
                onTap: () => showEntryEditor(context, entry: e),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CategoryBadge(
                      category: c.category(e.categoryId),
                      icon: e.kind == EntryKind.transfer
                          ? Icons.swap_horiz_rounded
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.payee.isNotEmpty
                                ? e.payee
                                : c.category(e.categoryId)?.name ?? 'Перевод',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${c.account(e.accountId)?.name ?? ''} · ${DateFormat('HH:mm').format(e.date.toLocal())}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Text(
                        '${e.kind == EntryKind.expense
                            ? '−'
                            : e.kind == EntryKind.income
                            ? '+'
                            : ''}${money(e.amountMinor, e.currency)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
