part of 'management.dart';

class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Бюджеты'),
        actions: [
          IconButton(
            tooltip: 'Создать бюджет',
            onPressed: () => _budgetEditor(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Планируйте спокойнее',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '${DateFormat('d MMMM', AppLanguage.intl).format(c.periodStart)} — ${DateFormat('d MMMM', AppLanguage.intl).format(c.periodEnd.subtract(const Duration(days: 1)))}',
          ),
          const SizedBox(height: 20),
          if (c.data.budgets.isEmpty)
            const EmptyState(
              'Бюджет — ваш ориентир',
              'Установите общий лимит или отдельный бюджет на категорию.',
            ),
          ...c.data.budgets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: BudgetCard(
                budget: b,
                onTap: () => _budgetEditor(context, budget: b),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BudgetCard extends StatelessWidget {
  const BudgetCard({super.key, required this.budget, this.onTap});
  final Budget budget;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final spent = FinanceEngine.budgetSpent(
      budget,
      c.data.entries,
      c.periodStart,
      c.periodEnd,
    );
    final ratio = budget.limitMinor > 0 ? spent / budget.limitMinor : 0.0;
    final elapsed = math.max(
      1,
      DateTime.now().difference(c.periodStart).inDays + 1,
    );
    final days = c.periodEnd.difference(c.periodStart).inDays;
    final forecast = (spent / elapsed * days).round();
    final color = ratio >= 1
        ? Theme.of(context).colorScheme.error
        : ratio >= .8
        ? const Color(0xFFD8AC65)
        : Theme.of(context).colorScheme.primary;
    return SurfaceCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                budget.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '${(ratio * 100).round()}%',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: .1),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${money(spent, budget.currency)} из ${money(budget.limitMinor, budget.currency)}',
          ),
          const SizedBox(height: 5),
          Text(
            '${spent > budget.limitMinor ? 'Превышение' : 'Осталось'} ${money((budget.limitMinor - spent).abs(), budget.currency)}',
            style: TextStyle(color: color),
          ),
          const SizedBox(height: 5),
          Text(
            'Прогноз: ${money(forecast, budget.currency)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

Future<void> _budgetEditor(BuildContext context, {Budget? budget}) async {
  final c = FinanceScope.of(context);
  final name = _text(budget?.name ?? '');
  final amount = _text(budget == null ? '' : _amount(budget.limitMinor));
  var currency = budget?.currency ?? c.currency;
  var category = budget?.categoryId ?? '';
  await _edit(
    context,
    title: budget == null ? 'Новый бюджет' : 'Бюджет',
    controllers: [name, amount],
    fields: (set) => [
      _field(name, 'Название', maxLength: 80, hint: 'Например: Еда и кафе'),
      _field(amount, 'Месячный лимит', amount: true, hint: 'Например: 30 000'),
      _select('Валюта', currency, {
        for (final v in currencies) v: v,
      }, (v) => set(() => currency = v)),
      _select('Категория', category, {
        '': 'Все расходы',
        for (final v in c.data.categories.where(
          (a) =>
              a.kind == EntryKind.expense &&
              (!a.archived || a.id == budget?.categoryId),
        ))
          v.id: v.name,
      }, (v) => set(() => category = v)),
    ],
    save: () async {
      final value = FinanceEngine.parseMinor(amount.text);
      if (value <= 0) {
        throw const FormatException('Лимит должен быть больше нуля.');
      }
      await c.saveBudget(
        Budget(
          id: budget?.id ?? c.id(),
          name: name.text.trim(),
          currency: currency,
          categoryId: category.isEmpty ? null : category,
          limitMinor: value,
        ),
      );
    },
    delete: budget == null
        ? null
        : () => c.mutate(
            (d) => d.copyWith(
              budgets: d.budgets.where((b) => b.id != budget.id).toList(),
            ),
          ),
  );
}
