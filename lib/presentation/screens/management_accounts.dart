part of 'management.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final active = c.data.accounts.where((a) => !a.archived).toList();
    final archived = c.data.accounts.where((a) => a.archived).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Счета'),
        actions: [
          IconButton(
            tooltip: 'Добавить счёт',
            onPressed: () => showAccountEditor(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (active.isEmpty)
            const EmptyState(
              'Добавьте первый счёт',
              'Карта, наличные или накопительный счёт — начните с того, чем пользуетесь каждый день.',
            ),
          ...active.map((a) => _accountCard(context, c, a)),
          if (archived.isNotEmpty) const SectionTitle('В архиве'),
          ...archived.map((a) => _accountCard(context, c, a)),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _accountCard(
    BuildContext context,
    FinanceController c,
    Account a,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: SurfaceCard(
      onTap: () => showAccountEditor(context, account: a),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryBadge(icon: categoryIcon(a.icon), color: Color(a.color)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      [
                        a.bank,
                        if (a.lastFour.isNotEmpty) '•• ${a.lastFour}',
                        if (a.archived) 'Архив',
                      ].where((e) => e.isNotEmpty).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.north_east_rounded, size: 19),
            ],
          ),
          const SizedBox(height: 24),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              money(FinanceEngine.balance(a, c.data.entries), a.currency),
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ),
          if (a.excluded)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Не включён в общий баланс'),
            ),
          if (a.creditLimitMinor > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Кредитный лимит ${money(a.creditLimitMinor, a.currency)}',
              ),
            ),
        ],
      ),
    ),
  );
}

Future<void> showAccountEditor(BuildContext context, {Account? account}) async {
  final c = FinanceScope.of(context);
  final a = account;
  final name = _text(a?.name ?? '');
  final opening = _text(_amount(a?.openingMinor ?? 0));
  final limit = _text(_amount(a?.creditLimitMinor ?? 0));
  final bank = _text(a?.bank ?? '');
  final last = _text(a?.lastFour ?? '');
  var type = a?.type ?? 'bank';
  var currency = a?.currency ?? c.currency;
  var excluded = a?.excluded ?? false;
  var archived = a?.archived ?? false;
  var color = a?.color ?? categoryColors.first;
  var icon = a?.icon ?? 26;
  const types = {
    'bank': 'Банковский счёт',
    'debit': 'Дебетовая карта',
    'credit': 'Кредитная карта',
    'cash': 'Наличные',
    'savings': 'Накопительный счёт',
    'deposit': 'Вклад',
    'investment': 'Инвестиции',
    'wallet': 'Электронный кошелёк',
    'other': 'Другой счёт',
  };
  final hasEntries =
      a != null &&
      (c.data.entries.any(
            (e) => e.accountId == a.id || e.toAccountId == a.id,
          ) ||
          c.data.recurring.any((r) => r.accountId == a.id));
  await _edit(
    context,
    title: a == null ? 'Новый счёт' : 'Настройка счёта',
    controllers: [name, opening, limit, bank, last],
    fields: (set) => [
      _field(name, 'Название', maxLength: 80),
      _select('Тип счёта', type, types, (v) => set(() => type = v)),
      _select(
        'Валюта',
        currency,
        {for (final v in currencies) v: v},
        (v) => set(() => currency = v),
        enabled: !hasEntries,
      ),
      if (hasEntries)
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Text(
            'Валюта фиксируется после первой операции или регулярного платежа.',
          ),
        ),
      _field(opening, 'Начальный баланс', amount: true),
      _field(limit, 'Кредитный лимит', amount: true),
      _optional(bank, 'Банк', maxLength: 80),
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          controller: last,
          decoration: const InputDecoration(labelText: 'Последние 4 цифры'),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          validator: (v) => (v ?? '').isNotEmpty && v!.length != 4
              ? 'Введите ровно 4 цифры'
              : null,
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CategoryBadge(icon: categoryIcon(icon), color: Color(color)),
        title: const Text('Иконка'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final result = await showIconPicker(
            context,
            icon: icon,
            color: color,
          );
          if (result != null) {
            set(() {
              icon = result.$1;
              color = result.$2;
            });
          }
        },
      ),
      _colors(color, (v) => set(() => color = v)),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Исключить из общего баланса'),
        value: excluded,
        onChanged: (v) => set(() => excluded = v),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('В архиве'),
        subtitle: const Text(
          'История сохранится; счёт не появится при добавлении операций.',
        ),
        value: archived,
        onChanged: (v) => set(() => archived = v),
      ),
    ],
    save: () async {
      final start = FinanceEngine.parseMinor(opening.text);
      final cap = FinanceEngine.parseMinor(limit.text);
      if (cap < 0) {
        throw const FormatException('Лимит не может быть отрицательным.');
      }
      await c.saveAccount(
        Account(
          id: a?.id ?? c.id(),
          name: name.text.trim(),
          type: type,
          currency: currency,
          openingMinor: start,
          creditLimitMinor: cap,
          bank: bank.text.trim(),
          lastFour: last.text,
          excluded: excluded,
          archived: archived,
          color: color,
          icon: icon,
        ),
      );
    },
    delete: a == null ? null : () => c.deleteAccount(a.id),
  );
}
