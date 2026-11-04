part of 'management.dart';

const frequencyNames = {
  'daily': 'Ежедневно',
  'weekly': 'Еженедельно',
  'monthly': 'Ежемесячно',
  'yearly': 'Ежегодно',
  'custom': 'Свой интервал в днях',
};

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final rules = [...c.data.recurring]
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Регулярные платежи'),
        actions: [
          IconButton(
            tooltip: 'Добавить платёж',
            onPressed: () => showRecurringEditor(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Планируйте обязательные платежи и регулярные доходы. Автоматические операции добавляются при открытии приложения.',
          ),
          const SizedBox(height: 20),
          if (rules.isEmpty)
            const EmptyState(
              'Всё под контролем',
              'Добавьте аренду, подписку или зарплату.',
            ),
          ...rules.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SurfaceCard(
                onTap: () => showRecurringEditor(context, rule: r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CategoryBadge(
                          category: c.category(r.categoryId),
                          icon: r.kind == EntryKind.income
                              ? Icons.south_west_rounded
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${DateFormat('d MMM', 'ru').format(r.nextDate)} · ${frequencyNames[r.frequency] ?? r.frequency}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      money(r.amountMinor, r.currency, c.hidden),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      r.enabled
                          ? (r.automatic ? 'Автоматически' : 'Напомнить')
                          : 'Приостановлен',
                      style: Theme.of(context).textTheme.bodySmall,
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

Future<void> showRecurringEditor(
  BuildContext context, {
  RecurringRule? rule,
}) async {
  final c = FinanceScope.of(context);
  final accounts = c.data.accounts.where((a) => !a.archived).toList();
  if (accounts.isEmpty) {
    showError(context, const FormatException('Сначала добавьте счёт.'));
    return;
  }
  final name = _text(rule?.name ?? '');
  final amount = _text(rule == null ? '' : _amount(rule.amountMinor));
  final interval = _text('${rule?.interval ?? 1}');
  var kind = rule?.kind ?? EntryKind.expense;
  var account = rule?.accountId ?? accounts.first.id;
  var category =
      rule?.categoryId ??
      c.data.categories.where((a) => a.kind == kind).firstOrNull?.id ??
      '';
  var frequency = rule?.frequency ?? 'monthly';
  var next = rule?.nextDate ?? DateTime.now().add(const Duration(days: 1));
  var anchorDay = rule?.anchorDay ?? next.day;
  var automatic = rule?.automatic ?? false;
  var enabled = rule?.enabled ?? true;
  await _edit(
    context,
    title: rule == null ? 'Новый регулярный платёж' : 'Регулярный платёж',
    controllers: [name, amount, interval],
    fields: (set) => [
      _field(name, 'Название', maxLength: 80),
      _select(
        'Тип',
        kind,
        const {EntryKind.expense: 'Расход', EntryKind.income: 'Доход'},
        (v) => set(() {
          kind = v;
          category =
              c.data.categories.where((a) => a.kind == kind).firstOrNull?.id ??
              '';
        }),
      ),
      _field(amount, 'Сумма', amount: true),
      _select('Счёт', account, {
        for (final a in c.data.accounts.where(
          (a) => !a.archived || a.id == account,
        ))
          a.id: '${a.name} · ${a.currency}',
      }, (v) => set(() => account = v)),
      _select('Категория', category, {
        if (!c.data.categories.any((a) => a.kind == kind))
          '': 'Сначала создайте категорию',
        for (final a in c.data.categories.where((a) => a.kind == kind))
          a.id: a.name,
      }, (v) => set(() => category = v)),
      _select(
        'Повтор',
        frequency,
        frequencyNames,
        (v) => set(() => frequency = v),
      ),
      _field(
        interval,
        frequency == 'custom'
            ? 'Каждые N дней'
            : 'Интервал (1 = каждый период)',
        amount: true,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.calendar_today_outlined),
        title: Text('Следующий: ${_date(next, c)}'),
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: next,
            firstDate: DateTime(1900),
            lastDate: DateTime(2200),
          );
          if (d != null) {
            set(() {
              next = d;
              anchorDay = d.day;
            });
          }
        },
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Автоматически создавать операцию'),
        subtitle: const Text('При следующем запуске в день платежа или позже.'),
        value: automatic,
        onChanged: (v) => set(() => automatic = v),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Активен'),
        value: enabled,
        onChanged: (v) => set(() => enabled = v),
      ),
    ],
    save: () async {
      final n = int.tryParse(interval.text);
      final m = FinanceEngine.parseMinor(amount.text);
      if (category.isEmpty) {
        throw const FormatException(
          'Сначала создайте категорию для этого типа операции.',
        );
      }
      if (n == null || n < 1 || n > 3650 || m <= 0) {
        throw const FormatException('Проверьте сумму и интервал от 1 до 3650.');
      }
      await c.saveRecurring(
        RecurringRule(
          id: rule?.id ?? c.id(),
          name: name.text.trim(),
          accountId: account,
          currency: c.account(account)!.currency,
          categoryId: category.isEmpty ? null : category,
          kind: kind,
          amountMinor: m,
          interval: n,
          frequency: frequency,
          nextDate: next,
          anchorDay: anchorDay,
          automatic: automatic,
          enabled: enabled,
        ),
      );
    },
    delete: rule == null
        ? null
        : () => c.mutate(
            (d) => d.copyWith(
              recurring: d.recurring.where((r) => r.id != rule.id).toList(),
            ),
          ),
  );
}
