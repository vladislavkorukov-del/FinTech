import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/finance_engine.dart';
import '../../domain/models.dart';
import '../controller.dart';
import '../widgets/common.dart';
import '../widgets/charts.dart';
import '../widgets/entry_tile.dart';
import 'management.dart';
import 'entry_editor.dart';
import 'transactions.dart';
import 'settings.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({
    super.key,
    required this.onTransactions,
    required this.onAnalytics,
  });
  final VoidCallback onTransactions, onAnalytics;
  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totals = FinanceEngine.totals(
      c.data.entries,
      c.periodStart,
      c.periodEnd,
      c.currency,
    );
    final previous = FinanceEngine.totals(
      c.data.entries,
      DateTime(c.periodStart.year, c.periodStart.month - 1, c.periodStart.day),
      c.periodStart,
      c.currency,
    );
    final difference = previous.expense == 0
        ? null
        : (totals.expense - previous.expense) / previous.expense * 100;
    final recent = [...c.data.entries]
      ..sort((a, b) => b.date.compareTo(a.date));
    final categories = FinanceEngine.categoryTotals(
      c.data.entries,
      c.periodStart,
      c.periodEnd,
      c.currency,
      EntryKind.expense,
    ).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final active = c.data.accounts.where((a) => !a.archived).toList();
    final archived = c.data.accounts.where((a) => a.archived).toList();
    final range = DateTimeRange(
      start: c.periodStart,
      end: DateTime(c.periodEnd.year, c.periodEnd.month, c.periodEnd.day - 1),
    );
    void operations(EntryKind kind) => _open(
      context,
      TransactionsScreen(initialKind: kind, initialRange: range),
    );
    void category(String id) =>
        _open(context, TransactionsScreen(categoryId: id, initialRange: range));
    return ListView(
      key: const PageStorageKey('dashboard'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF070807),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.blur_on_rounded,
                color: Color(0xFFC5E768),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'FINORA',
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 2),
              ),
            ),
            IconButton(
              tooltip: 'Настройки',
              onPressed: () => _open(context, const SettingsScreen()),
              icon: const Icon(Icons.tune_rounded),
            ),
            IconButton(
              tooltip: c.hidden ? 'Показать суммы' : 'Скрыть суммы',
              onPressed: () async {
                try {
                  await c.preferences(
                    c.data.preferences.copyWith(hideAmounts: !c.hidden),
                  );
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
              icon: Icon(
                c.hidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('Мои финансы', style: theme.textTheme.headlineLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Всё важное. В одном месте.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () => _open(context, const MembersScreen()),
              child: const Text('Моя семья'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Material(
          color: const Color(0xFF070807),
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            onTap: () => _open(context, const AccountsScreen()),
            borderRadius: BorderRadius.circular(28),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF070807), Color(0xFF1F2321)],
                ),
              ),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Color(0xFFFCFEFA)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'ОБЩИЙ БАЛАНС',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFACAEA9),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC5E768),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            c.currency,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF070807),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        money(c.balance, c.currency, c.hidden),
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(
                          Icons.north_east_rounded,
                          color: Color(0xFFC5E768),
                          size: 17,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'За месяц ${totals.net >= 0 ? '+' : ''}${money(totals.net, c.currency, c.hidden)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFC5E768),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Счета и средства, переведённые в мечты',
                      style: TextStyle(fontSize: 10, color: Color(0xFFACAEA9)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _SummaryTile(
                title: 'Доходы',
                amount: totals.income,
                currency: c.currency,
                hidden: c.hidden,
                icon: Icons.south_west_rounded,
                onTap: () => operations(EntryKind.income),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryTile(
                title: 'Расходы',
                amount: totals.expense,
                currency: c.currency,
                hidden: c.hidden,
                icon: Icons.north_east_rounded,
                onTap: () => operations(EntryKind.expense),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            for (final action in [
              (EntryKind.expense, 'Расход', Icons.remove_rounded),
              (EntryKind.income, 'Доход', Icons.add_rounded),
              (EntryKind.transfer, 'Перевод', Icons.swap_horiz_rounded),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilledButton.tonal(
                    onPressed: () => showEntryEditor(context, kind: action.$1),
                    style: FilledButton.styleFrom(
                      backgroundColor: action.$1 == EntryKind.expense
                          ? scheme.primary
                          : scheme.surface,
                      foregroundColor: action.$1 == EntryKind.expense
                          ? scheme.onPrimary
                          : scheme.onSurface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 17,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: .5),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(action.$3, size: 23),
                        const SizedBox(height: 7),
                        Text(
                          action.$2,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (c.data.demo)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Row(
              children: [
                Icon(
                  Icons.science_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Демонстрационный семейный профиль',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SectionTitle(
          'Все счета',
          action: '+ Счёт',
          onTap: () => showAccountEditor(context),
        ),
        if (active.isEmpty)
          SurfaceCard(
            onTap: () => showAccountEditor(context),
            child: const EmptyState(
              'Добавьте первый счёт',
              'Карты, наличные, вклады — все деньги будут здесь.',
              icon: Icons.add_card_outlined,
            ),
          ),
        for (final account in active)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AccountRow(account: account),
          ),
        if (archived.isNotEmpty)
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              key: const PageStorageKey('dashboard-archived-accounts'),
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                'Архивные счета · ${archived.length}',
                style: theme.textTheme.titleMedium,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: archived
                  .map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _AccountRow(account: a),
                    ),
                  )
                  .toList(),
            ),
          ),
        SectionTitle(
          'Обзор месяца',
          action: DateFormat('LLLL', 'ru').format(DateTime.now()),
          onTap: () => _open(context, const CalendarScreen()),
        ),
        _ExpenseOverview(
          categories: categories,
          total: totals.expense,
          difference: difference,
          onAnalytics: onAnalytics,
          onCategory: category,
        ),
        SectionTitle(
          'Мечты и накопления',
          action: 'Все мечты',
          onTap: () => _open(context, const GoalsScreen()),
        ),
        if (c.data.goals.isEmpty)
          SurfaceCard(
            onTap: () => _open(context, const GoalsScreen()),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_outlined),
                SizedBox(width: 14),
                Expanded(
                  child: Text('Создайте мечту и переводите на неё деньги'),
                ),
              ],
            ),
          )
        else
          for (final goal in c.data.goals)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DreamRow(goal: goal),
            ),
        const _PaymentSection(
          paymentType: 'subscription',
          title: 'Подписки',
          icon: Icons.subscriptions_outlined,
        ),
        const _PaymentSection(
          paymentType: 'mandatory',
          title: 'Обязательные платежи',
          icon: Icons.receipt_long_outlined,
        ),
        SectionTitle(
          'Последние операции',
          action: 'Все',
          onTap: onTransactions,
        ),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: recent.isEmpty
              ? const EmptyState(
                  'История начинается здесь',
                  'Добавьте первую операцию кнопкой +.',
                )
              : Column(
                  children: recent.take(5).map((e) => EntryTile(e)).toList(),
                ),
        ),
        SectionTitle(
          'Бюджет под контролем',
          action: 'Настроить',
          onTap: () => _open(context, const BudgetsScreen()),
        ),
        if (c.data.budgets.isEmpty)
          SurfaceCard(
            onTap: () => _open(context, const BudgetsScreen()),
            child: const Text(
              'Установите месячный лимит и планируйте расходы.',
            ),
          )
        else
          for (final budget in c.data.budgets.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SurfaceCard(
                onTap: () => _open(context, const BudgetsScreen()),
                child: Builder(
                  builder: (context) {
                    final spent = FinanceEngine.budgetSpent(
                      budget,
                      c.data.entries,
                      c.periodStart,
                      c.periodEnd,
                    );
                    final ratio = spent / budget.limitMinor;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(budget.name, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: ratio.clamp(0, 1),
                          minHeight: 7,
                          borderRadius: BorderRadius.circular(8),
                          color: ratio >= 1 ? scheme.error : scheme.primary,
                          backgroundColor: scheme.outlineVariant.withValues(
                            alpha: .35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${money(spent, budget.currency, c.hidden)} из ${money(budget.limitMinor, budget.currency, c.hidden)} · ${(ratio * 100).round()}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
        const SizedBox(height: 24),
        Text(
          'Уверенность начинается с ясности.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account});
  final Account account;
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 18),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => TransactionsScreen(accountId: account.id),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF1F2321),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              categoryIcon(account.icon),
              color: const Color(0xFFC5E768),
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  [
                        if (account.bank.isNotEmpty) account.bank,
                        if (account.lastFour.isNotEmpty)
                          '•• ${account.lastFour}',
                        if (account.excluded) 'Вне общего баланса',
                      ].join(' · ').isEmpty
                      ? account.currency
                      : [
                          if (account.bank.isNotEmpty) account.bank,
                          if (account.lastFour.isNotEmpty)
                            '•• ${account.lastFour}',
                          if (account.excluded) 'Вне общего баланса',
                        ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * .29,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                money(
                  FinanceEngine.balance(account, c.data.entries),
                  account.currency,
                  c.hidden,
                ),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.5,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Настроить счёт ${account.name}',
            visualDensity: VisualDensity.compact,
            onPressed: () => showAccountEditor(context, account: account),
            icon: Icon(
              Icons.more_horiz_rounded,
              color: scheme.onSurfaceVariant,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }
}

class _DreamRow extends StatelessWidget {
  const _DreamRow({required this.goal});
  final Goal goal;
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final saved = FinanceEngine.goalSaved(goal, c.data.entries);
    final percent = (saved / goal.targetMinor * 100).round();
    return SurfaceCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => TransactionsScreen(goalId: goal.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryBadge(
                icon: categoryIcon(goal.icon),
                color: scheme.onSurface,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  goal.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Пополнить мечту ${goal.name}',
                onPressed: () => showEntryEditor(
                  context,
                  kind: EntryKind.transfer,
                  goalId: goal.id,
                ),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: (saved / goal.targetMinor).clamp(0, 1),
            minHeight: 6,
            borderRadius: BorderRadius.circular(8),
            color: scheme.primary,
            backgroundColor: scheme.outlineVariant.withValues(alpha: .3),
          ),
          const SizedBox(height: 10),
          Text(
            '${money(saved, goal.currency, c.hidden)} · $percent% накоплено',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PaymentSection extends StatelessWidget {
  const _PaymentSection({
    required this.paymentType,
    required this.title,
    required this.icon,
  });
  final String paymentType, title;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final rules =
        c.data.recurring
            .where(
              (r) =>
                  r.enabled &&
                  r.kind == EntryKind.expense &&
                  r.paymentType == paymentType,
            )
            .toList()
          ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          title,
          action: 'Все',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RecurringScreen(initialPaymentType: paymentType),
            ),
          ),
        ),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              if (rules.isEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icon),
                  title: Text(
                    paymentType == 'subscription'
                        ? 'Добавить подписку'
                        : 'Добавить обязательный платёж',
                  ),
                  subtitle: Text(
                    paymentType == 'subscription'
                        ? 'Сервисы, музыка, связь'
                        : 'Кредит, ипотека, аренда',
                  ),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () =>
                      showRecurringEditor(context, paymentType: paymentType),
                )
              else
                for (final r in rules.take(3))
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: CategoryBadge(icon: icon, color: scheme.onSurface),
                    title: Text(
                      r.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      '${DateFormat('d MMM', 'ru').format(r.nextDate)} · ${r.automatic ? 'автозапись' : 'напоминание'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * .3,
                      ),
                      child: Text(
                        money(r.amountMinor, r.currency, c.hidden),
                        maxLines: 2,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    onTap: () => showRecurringEditor(context, rule: r),
                  ),
              if (rules.isNotEmpty)
                TextButton.icon(
                  onPressed: () =>
                      showRecurringEditor(context, paymentType: paymentType),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: Text(
                    paymentType == 'subscription'
                        ? 'Добавить подписку'
                        : 'Добавить платёж',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.title,
    required this.amount,
    required this.currency,
    required this.hidden,
    required this.icon,
    required this.onTap,
  });
  final String title, currency;
  final int amount;
  final bool hidden;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: onTap,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            money(amount, currency, hidden),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    ),
  );
}

class _ExpenseOverview extends StatelessWidget {
  const _ExpenseOverview({
    required this.categories,
    required this.total,
    required this.difference,
    required this.onAnalytics,
    required this.onCategory,
  });
  final List<MapEntry<String, int>> categories;
  final int total;
  final double? difference;
  final VoidCallback onAnalytics;
  final ValueChanged<String> onCategory;
  Color shade(int i) => Color.lerp(
    const Color(0xFFC5E768),
    const Color(0xFF434840),
    i / categories.length.clamp(1, 100),
  )!;
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final theme = Theme.of(context);
    return SurfaceCard(
      onTap: onAnalytics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Куда уходят деньги',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.arrow_outward_rounded, size: 18),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                SizedBox(
                  width: constraints.maxWidth * .43,
                  child: DonutChart(
                    values: categories.map((e) => e.value).toList(),
                    colors: List.generate(categories.length, shade),
                    onSelect: (i) => onCategory(categories[i].key),
                    center: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${categories.length}',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const Text('категорий', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      for (final item in categories.take(3))
                        InkWell(
                          onTap: () => onCategory(item.key),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: shade(categories.indexOf(item)),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    c.category(item.key)?.name ?? 'Прочее',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                Text(
                                  '${total == 0 ? 0 : (item.value / total * 100).round()}%',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            difference == null
                ? 'Добавьте прошлый месяц для сравнения'
                : 'На ${difference!.abs().round()}% ${difference! <= 0 ? 'меньше' : 'больше'}, чем в прошлом месяце',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
