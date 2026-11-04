part of 'management.dart';

const frequencyNames = {
  'daily': 'Ежедневно',
  'weekly': 'Еженедельно',
  'monthly': 'Ежемесячно',
  'yearly': 'Ежегодно',
  'custom': 'Свой интервал в днях',
};

const paymentTypeNames = {
  'subscription': 'Подписка',
  'mandatory': 'Обязательный платёж',
};

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key, this.initialPaymentType});
  final String? initialPaymentType;
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  late String filter =
      const ['subscription', 'mandatory'].contains(widget.initialPaymentType)
      ? widget.initialPaymentType!
      : 'all';

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final rules = [...c.data.recurring]
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    final subscriptions = rules
        .where(
          (r) => r.kind == EntryKind.expense && r.paymentType == 'subscription',
        )
        .toList();
    final mandatory = rules
        .where(
          (r) => r.kind == EntryKind.expense && r.paymentType == 'mandatory',
        )
        .toList();
    final incomes = rules.where((r) => r.kind == EntryKind.income).toList();
    final shown = filter == 'subscription'
        ? subscriptions
        : filter == 'mandatory'
        ? mandatory
        : filter == 'income'
        ? incomes
        : rules;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          filter == 'subscription'
              ? 'Подписки'
              : filter == 'mandatory'
              ? 'Обязательные платежи'
              : 'Регулярные операции',
        ),
        actions: [
          IconButton(
            tooltip: filter == 'subscription'
                ? 'Добавить подписку'
                : filter == 'income'
                ? 'Добавить регулярный доход'
                : 'Добавить платёж',
            onPressed: () => showRecurringEditor(
              context,
              paymentType: filter == 'subscription'
                  ? 'subscription'
                  : 'mandatory',
              initialKind: filter == 'income'
                  ? EntryKind.income
                  : EntryKind.expense,
            ),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            filter == 'subscription'
                ? 'Сервисы, которыми вы пользуетесь. Следите за продлениями и отменяйте лишнее вовремя.'
                : filter == 'mandatory'
                ? 'Аренда, ипотека, коммунальные услуги и кредиты. Планируйте важное заранее.'
                : 'Подписки, обязательные платежи и доходы — отдельно, чтобы ничего не упустить.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                const {
                      'all': 'Все',
                      'subscription': 'Подписки',
                      'mandatory': 'Обязательные',
                      'income': 'Доходы',
                    }.entries
                    .map(
                      (entry) => ChoiceChip(
                        key: ValueKey('payment-filter-${entry.key}'),
                        label: Text(entry.value),
                        selected: filter == entry.key,
                        onSelected: (_) => setState(() => filter = entry.key),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            EmptyState(
              filter == 'subscription'
                  ? 'Подписок пока нет'
                  : filter == 'mandatory'
                  ? 'Важное под контролем'
                  : filter == 'income'
                  ? 'Запланируйте доход'
                  : 'Всё под контролем',
              filter == 'subscription'
                  ? 'Добавьте сервис, выберите сумму и дату следующего продления.'
                  : filter == 'income'
                  ? 'Добавьте зарплату, проценты или другой регулярный доход.'
                  : 'Добавьте реальный платёж, его сумму и дату. Операции создаются при запуске приложения.',
            ),
          if ((filter == 'all' || filter == 'subscription') &&
              subscriptions.isNotEmpty) ...[
            const SectionTitle('Подписки'),
            ...subscriptions.map((r) => _ruleCard(context, c, r)),
          ],
          if ((filter == 'all' || filter == 'mandatory') &&
              mandatory.isNotEmpty) ...[
            const SectionTitle('Обязательные платежи'),
            ...mandatory.map((r) => _ruleCard(context, c, r)),
          ],
          if ((filter == 'all' || filter == 'income') &&
              incomes.isNotEmpty) ...[
            const SectionTitle('Регулярные доходы'),
            ...incomes.map((r) => _ruleCard(context, c, r)),
          ],
        ],
      ),
    );
  }

  Widget _ruleCard(
    BuildContext context,
    FinanceController c,
    RecurringRule r,
  ) => Padding(
    key: ValueKey('payment-rule-${r.id}'),
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
                ? (r.automatic ? 'Автоматически при запуске' : 'Напоминание')
                : 'Приостановлен',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

Future<void> showRecurringEditor(
  BuildContext context, {
  RecurringRule? rule,
  String? paymentType,
  EntryKind initialKind = EntryKind.expense,
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
  var kind = rule?.kind ?? initialKind;
  var selectedPaymentType =
      rule?.paymentType ??
      (paymentType == 'subscription' ? 'subscription' : 'mandatory');
  if (kind == EntryKind.income) selectedPaymentType = 'mandatory';
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
    title: rule == null
        ? selectedPaymentType == 'subscription'
              ? 'Новая подписка'
              : 'Новая регулярная операция'
        : 'Регулярная операция',
    controllers: [name, amount, interval],
    fields: (set) => [
      _field(name, 'Название', maxLength: 80),
      _select(
        'Тип',
        kind,
        const {EntryKind.expense: 'Расход', EntryKind.income: 'Доход'},
        (v) => set(() {
          kind = v;
          if (kind == EntryKind.income) selectedPaymentType = 'mandatory';
          category =
              c.data.categories.where((a) => a.kind == kind).firstOrNull?.id ??
              '';
        }),
      ),
      if (kind == EntryKind.expense)
        _select(
          'Вид платежа',
          selectedPaymentType,
          paymentTypeNames,
          (v) => set(() => selectedPaymentType = v),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          kind == EntryKind.income
              ? 'Зарплата, проценты и другие доходы не относятся к подпискам.'
              : selectedPaymentType == 'subscription'
              ? 'Музыка, кино, облако и другие сервисы. Выберите реальную дату продления.'
              : 'Аренда, ипотека, кредиты и коммунальные услуги.',
        ),
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
          paymentType: kind == EntryKind.income
              ? 'mandatory'
              : selectedPaymentType,
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
