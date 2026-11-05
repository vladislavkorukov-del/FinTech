import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/finance_engine.dart';
import '../../domain/models.dart';
import '../controller.dart';
import '../widgets/common.dart';
import '../widgets/entry_tile.dart';
import 'management.dart';
import 'entry_editor.dart';
import 'transactions.dart';
import '../widgets/finance_header.dart';
import '../widgets/finance_quick_actions.dart';
import '../widgets/bank_picker.dart';
import '../widgets/category_orbit_chart.dart';
import '../widgets/service_badge.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final colors = FinanceColors.of(context);
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
    return ListView(
      key: const PageStorageKey('dashboard'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        const FinanceHeader(),
        const SizedBox(height: 10),
        Row(
          key: const ValueKey('dashboard-month-summary'),
          children: [
            Expanded(
              child: _SummaryTile(
                title: 'Доходы',
                amount: totals.income,
                currency: c.currency,
                icon: Icons.south_west_rounded,
                onTap: () => operations(EntryKind.income),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryTile(
                title: 'Расходы',
                amount: totals.expense,
                currency: c.currency,
                icon: Icons.north_east_rounded,
                onTap: () => operations(EntryKind.expense),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const FinanceQuickActions(),
        SectionTitle(
          'Все счета',
          action: '+ Счёт',
          onTap: () => showAccountEditor(context),
        ),
        if (active.isEmpty)
          SurfaceCard(
            onTap: () => showAccountEditor(context),
            child: const EmptyState(
              'Добавьте счёт',
              'Карта, наличные, вклад или кошелёк.',
              icon: Icons.add_card_outlined,
            ),
          ),
        for (final account in active)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
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
                style: Theme.of(context).textTheme.titleMedium,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: archived
                  .map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(top: 6),
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
          onCategory: (id) => _open(
            context,
            TransactionsScreen(categoryId: id, initialRange: range),
          ),
        ),
        SectionTitle(
          'Мечты и накопления',
          action: 'Все',
          onTap: () => _open(context, const GoalsScreen()),
        ),
        if (c.data.goals.isEmpty)
          SurfaceCard(
            onTap: () => _open(context, const GoalsScreen()),
            child: const EmptyState(
              'Нет целей накоплений',
              'Добавьте цель, сумму и срок.',
              icon: Icons.savings_outlined,
            ),
          )
        else
          for (final goal in c.data.goals)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
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
                  'Операций нет',
                  'Добавьте доход, расход или перевод.',
                )
              : Column(
                  children: recent.take(5).map((e) => EntryTile(e)).toList(),
                ),
        ),
        SectionTitle(
          'Бюджеты',
          action: 'Все',
          onTap: () => _open(context, const BudgetsScreen()),
        ),
        if (c.data.budgets.isEmpty)
          SurfaceCard(
            onTap: () => _open(context, const BudgetsScreen()),
            child: const EmptyState(
              'Бюджет не задан',
              'Установите общий лимит или лимиты категорий.',
            ),
          )
        else
          for (final budget in c.data.budgets.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                onTap: () => _open(context, const BudgetsScreen()),
                child: Builder(
                  builder: (context) {
                    final spent = FinanceEngine.budgetSpent(
                      budget,
                      c.data.entries,
                      c.periodStart,
                      c.periodEnd,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          budget.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: (spent / budget.limitMinor).clamp(0, 1),
                          color: spent > budget.limitMinor
                              ? colors.expense
                              : scheme.primary,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${money(spent, budget.currency)} из ${money(budget.limitMinor, budget.currency)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    );
                  },
                ),
              ),
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
      padding: const EdgeInsets.fromLTRB(14, 11, 4, 11),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => TransactionsScreen(accountId: account.id),
        ),
      ),
      child: Row(
        children: [
          bankLogoFor(account.bank, size: 38) ??
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: FinanceColors.of(context).iconBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  categoryIcon(account.icon),
                  color: FinanceColors.of(context).iconForeground,
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
                const SizedBox(height: 3),
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
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
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
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (saved / goal.targetMinor).clamp(0, 1),
            minHeight: 6,
            borderRadius: BorderRadius.circular(8),
            color: scheme.primary,
            backgroundColor: scheme.outlineVariant.withValues(alpha: .3),
          ),
          const SizedBox(height: 8),
          Text(
            '${money(saved, goal.currency)} · $percent% накоплено',
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 2),
                    leading: ServiceBadge(
                      serviceId: r.serviceId,
                      customIconPath: r.customIconPath,
                      name: r.name,
                    ),
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
                        money(r.amountMinor, r.currency),
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
    required this.icon,
    required this.onTap,
  });
  final String title, currency;
  final int amount;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 17,
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
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            money(amount, currency),
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
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Расходы по категориям',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Открыть аналитику',
                onPressed: onAnalytics,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
              ),
            ],
          ),
          CategoryOrbitChart(
            slices: categories.map((e) {
              final category = c.category(e.key);
              return CategorySlice(
                id: e.key,
                name: category?.name ?? 'Прочее',
                icon: categoryIcon(category?.icon ?? 19),
                color: Color(
                  category?.color ??
                      categoryColors[e.key.hashCode.abs() %
                          categoryColors.length],
                ),
                amount: e.value,
              );
            }).toList(),
            currency: c.currency,
            onDetails: onCategory,
          ),
          if (difference != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'На ${difference!.abs().round()}% ${difference! <= 0 ? 'меньше' : 'больше'}, чем в прошлом месяце',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
