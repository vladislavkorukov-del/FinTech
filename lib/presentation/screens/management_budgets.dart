part of 'management.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});
  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  @override
  void initState() {
    super.initState();
    // 1.44: looking at the budgets is a day of keeping the books.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(FinanceScope.of(context).noteActivity());
    });
  }

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
    final scheme = Theme.of(context).colorScheme;
    final over = spent > budget.limitMinor;
    // Release: a compact card — name and share on one line, a thin bar,
    // spent of limit on the left and what is left on the right.
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  budget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(ratio * 100).round()}%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              minHeight: 6,
              color: color,
              backgroundColor: scheme.onSurface.withValues(alpha: .08),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      money(spent, budget.currency),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        ' из ${money(budget.limitMinor, budget.currency)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${over ? 'Превышение' : 'Осталось'} ${money((budget.limitMinor - spent).abs(), budget.currency)}',
                style: TextStyle(
                  color: over ? scheme.error : scheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Прогноз: ${money(forecast, budget.currency)}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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
