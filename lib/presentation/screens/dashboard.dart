import '../i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:intl/intl.dart';

import '../../domain/finance_engine.dart';
import '../../domain/models.dart';
import '../controller.dart';
import '../widgets/common.dart';
import '../widgets/grouped_list.dart';
import '../widgets/money_tips.dart';
import '../widgets/entry_tile.dart';
import 'management.dart';
import 'entry_editor.dart';
import 'payee_summary_screen.dart';
import 'transactions.dart';
import '../widgets/finance_header.dart';
import '../widgets/finance_quick_actions.dart';
import '../widgets/motion.dart';
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
    final prefs = c.data.preferences;
    // Saved against the current settings, never a stale copy, so two quick
    // drags do not undo each other.
    void Function(List<String>) save(
      AppPreferences Function(AppPreferences, List<String>) apply,
    ) =>
        (List<String> ids) =>
            c.mutate((d) => d.copyWith(preferences: apply(d.preferences, ids)));

    final accounts = AppPreferences.arrange(
      active,
      prefs.accountOrder,
      (a) => a.id,
    );
    final goals = AppPreferences.arrange(
      c.data.goals,
      prefs.goalOrder,
      (g) => g.id,
    );
    Widget block(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
    final blocks = <String, Widget>{
      'summary': Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Row(
          key: const ValueKey('dashboard-month-summary'),
          children: [
            Expanded(
              child: _SummaryTile(
                title: tr('Доходы'),
                amount: totals.income,
                currency: c.currency,
                icon: Icons.south_west_rounded,
                tone: colors.income,
                onTap: () => operations(EntryKind.income),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryTile(
                title: tr('Расходы'),
                amount: totals.expense,
                currency: c.currency,
                icon: Icons.north_east_rounded,
                tone: colors.expense,
                onTap: () => operations(EntryKind.expense),
              ),
            ),
          ],
        ),
      ),
      'quick': const FinanceQuickActions(),
      'accounts': block([
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
        _Reorderable(
          listKey: 'dashboard-accounts',
          ids: prefs.accountOrder,
          onSave: save((p, ids) => p.copyWith(accountOrder: ids)),
          items: {
            for (final account in accounts)
              // 1.28: swipe left to delete.
              account.id: SwipeToDelete(
                key: ValueKey('swipe-dash-account-${account.id}'),
                margin: const EdgeInsets.only(bottom: 6),
                title: 'Удалить счёт «${account.name}»?',
                message:
                    'Счёт с операциями удалить нельзя — его можно '
                    'отправить в архив в редакторе счёта.',
                onDelete: () => c.deleteAccount(account.id),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _AccountRow(account: account),
                ),
              ),
          },
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
      ]),
      'overview': block([
        SectionTitle(
          tr('Обзор месяца'),
          action: tr('Календарь'),
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
      ]),
      'goals': block([
        SectionTitle(
          tr('Мечты и накопления'),
          action: tr('Все'),
          onTap: () => _open(context, const GoalsScreen()),
        ),
        if (goals.isEmpty)
          SurfaceCard(
            onTap: () => _open(context, const GoalsScreen()),
            child: const EmptyState(
              'Нет целей накоплений',
              'Добавьте цель, сумму и срок.',
              icon: Icons.savings_outlined,
            ),
          )
        else
          _Reorderable(
            listKey: 'dashboard-goals',
            ids: prefs.goalOrder,
            onSave: save((p, ids) => p.copyWith(goalOrder: ids)),
            items: {
              for (final goal in goals)
                goal.id: SwipeToDelete(
                  key: ValueKey('swipe-dash-goal-${goal.id}'),
                  margin: const EdgeInsets.only(bottom: 6),
                  title: 'Удалить мечту «${goal.name}»?',
                  message:
                      'Мечту с пополнениями удалить нельзя — сначала '
                      'уберите пополнения.',
                  onDelete: () => c.deleteGoal(goal.id),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _DreamRow(goal: goal),
                  ),
                ),
            },
          ),
      ]),
      // 1.33: subscriptions and required payments (loans, rent…) together.
      'subscriptions': _PaymentSection(
        title: tr('Платежи и подписки'),
        icon: Icons.event_repeat_outlined,
      ),
      'recent': block([
        SectionTitle(
          tr('Последние операции'),
          action: tr('Все'),
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
                  children: recent
                      .take(5)
                      .map(
                        (e) => EntryTile(
                          e,
                          // Payee summary with a period choice; transfers and
                          // operations without a payee open the editor.
                          onTap:
                              e.kind == EntryKind.transfer ||
                                  e.payee.trim().isEmpty
                              ? null
                              : () => _open(
                                  context,
                                  PayeeSummaryScreen(entry: e),
                                ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ]),
      'budgets': block([
        SectionTitle(
          tr('Бюджеты'),
          action: tr('Все'),
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
      ]),
      // 1.28: a money tip from Finora; swipe it away or turn it off.
      // 1.30: at the very bottom unless the person drags it elsewhere.
      if (prefs.tips) 'tips': const MoneyTipsCard(),
    };
    // 1.14: every block can be dragged to a new place with a long press;
    // accounts and goals inside their blocks too. The order is saved.
    return _Reorderable(
      listKey: 'dashboard',
      ids: prefs.tipsMoved
          ? prefs.dashboardOrder
          : prefs.dashboardOrder.where((id) => id != 'tips').toList(),
      onSave: save(
        (p, ids) => p.copyWith(
          dashboardOrder: ids,
          tipsMoved:
              p.tipsMoved || (ids.contains('tips') && ids.last != 'tips'),
        ),
      ),
      nested: false,
      header: const Reveal(index: 0, child: FinanceHeader()),
      // 1.26: no hint here any more — the tour explains dragging.
      footer: const SizedBox(height: 18),

      // 1.9: sections arrive in a short cascade.
      wrap: (i, child) => Reveal(index: i + 1, child: child),
      items: blocks,
    );
  }
}

/// A dragged block or row: lifted slightly, without the default grey card.
Widget _lifted(Widget child, int index, Animation<double> animation) =>
    AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = Curves.easeOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + .03 * t,
          child: Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .28 * t),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
    );

/// A list whose items are dragged into a new order with a long press. The
/// new order shows at once and is then saved through [onSave]; [ids] is the
/// saved order (unknown ids ignored, new items last). A nested list (accounts,
/// goals inside a block) does not scroll by itself.
class _Reorderable extends StatefulWidget {
  const _Reorderable({
    required this.listKey,
    required this.ids,
    required this.items,
    required this.onSave,
    this.nested = true,
    this.header,
    this.footer,
    this.wrap,
  });
  final String listKey;
  final List<String> ids;
  final Map<String, Widget> items;
  final void Function(List<String>) onSave;
  final bool nested;
  final Widget? header, footer;
  final Widget Function(int index, Widget child)? wrap;
  @override
  State<_Reorderable> createState() => _ReorderableState();
}

class _ReorderableState extends State<_Reorderable> {
  List<String>? _local;

  @override
  void didUpdateWidget(covariant _Reorderable old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.ids, widget.ids)) _local = null;
  }

  @override
  Widget build(BuildContext context) {
    final order = AppPreferences.arrange(
      widget.items.keys.toList(),
      _local ?? widget.ids,
      (id) => id,
    );
    void reorder(int from, int to) {
      // [to] is the final place, already adjusted for the moved item.
      final next = [...order];
      next.insert(to, next.removeAt(from));
      if (listEquals(next, order)) return;
      setState(() => _local = next);
      widget.onSave(next);
    }

    return ReorderableListView(
      key: widget.nested
          ? ValueKey(widget.listKey)
          : PageStorageKey(widget.listKey),
      shrinkWrap: widget.nested,
      physics: widget.nested ? const NeverScrollableScrollPhysics() : null,
      padding: widget.nested
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 4, 16, 20),
      buildDefaultDragHandles: false,
      proxyDecorator: _lifted,
      header: widget.header,
      footer: widget.footer,
      onReorderItem: reorder,
      children: [
        for (var i = 0; i < order.length; i++)
          ReorderableDelayedDragStartListener(
            key: ValueKey('${widget.listKey}-${order[i]}'),
            index: i,
            child:
                widget.wrap?.call(i, widget.items[order[i]]!) ??
                widget.items[order[i]]!,
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
          accountBankLogo(context, account, size: 38) ??
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
  const _PaymentSection({required this.title, required this.icon});
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final rules =
        c.data.recurring
            .where((r) => r.enabled && r.kind == EntryKind.expense)
            .toList()
          ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          title,
          action: tr('Все'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const RecurringScreen()),
          ),
        ),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              if (rules.isEmpty) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.subscriptions_outlined),
                  title: const Text('Добавить подписку'),
                  subtitle: const Text('Сервисы, музыка, связь'),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () =>
                      showRecurringEditor(context, paymentType: 'subscription'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Добавить обязательный платёж'),
                  subtitle: const Text('Кредит, ипотека, аренда, коммуналка'),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () =>
                      showRecurringEditor(context, paymentType: 'mandatory'),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Text(
                    'В месяц ≈ ${money(_monthly(rules, c.currency), c.currency)}',
                    key: const ValueKey('payments-monthly'),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final r in rules.take(5))
                  SwipeToDelete(
                    key: ValueKey('swipe-dash-rule-${r.id}'),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    title: 'Удалить «${r.name}»?',
                    message:
                        'Платёж больше не будет напоминать о себе. '
                        'Записанные операции останутся.',
                    onDelete: () => FinanceScope.of(context).mutate(
                      (d) => d.copyWith(
                        recurring: d.recurring
                            .where((x) => x.id != r.id)
                            .toList(),
                      ),
                    ),
                    child: ListTile(
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
                        '${DateFormat('d MMM', 'ru').format(r.nextDate)} · ${r.paymentType == 'subscription' ? 'подписка' : 'обязательный'}${r.kind == EntryKind.expense
                            ? ''
                            : r.automatic
                            ? 'автозапись'
                            : 'напоминание'}',
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
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        key: const ValueKey('payments-add-subscription'),
                        onPressed: () => showRecurringEditor(
                          context,
                          paymentType: 'subscription',
                        ),
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('Подписка'),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        key: const ValueKey('payments-add-mandatory'),
                        onPressed: () => showRecurringEditor(
                          context,
                          paymentType: 'mandatory',
                        ),
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('Платёж'),
                      ),
                    ),
                  ],
                ),
              ],
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
    required this.tone,
  });
  final String title, currency;
  final int amount;
  final IconData icon;
  final VoidCallback onTap;

  /// Income or expense color: the card is tinted with it.
  final Color tone;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 1.16: a neutral card; the color stays only in the small arrow.
    return PressScale(
      child: KeyedSubtree(
        key: ValueKey('summary-$title'),
        // 1.17: compact — tighter padding, a smaller amount, minimal gap.
        child: GlassSurface(
          radius: 18,
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 13, color: tone),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              // A fixed line, so both tiles are always the same height even
              // when a long amount is scaled down to fit.
              SizedBox(
                height: 21 * MediaQuery.textScalerOf(context).scale(1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedMoney(
                    amount,
                    currency: currency,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    final month = DateFormat('LLLL', 'ru').format(DateTime.now());
    final scheme = Theme.of(context).colorScheme;
    // 1.26: one compact ring, the month in the middle.
    return SurfaceCard(
      key: const ValueKey('expense-overview'),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Column(
        children: [
          CategoryOrbitChart(
            title: month[0].toUpperCase() + month.substring(1),
            diameter: 190,
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
          Row(
            children: [
              Expanded(
                child: difference == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          'На ${difference!.abs().round()}% ${difference! <= 0 ? 'меньше' : 'больше'}, чем в прошлом месяце',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
              TextButton(onPressed: onAnalytics, child: Text(tr('Аналитика'))),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the expense payments come to in a month (1.33), in [currency].
int _monthly(List<RecurringRule> rules, String currency) {
  var total = 0.0;
  for (final r in rules) {
    if (r.currency != currency) continue;
    final per = switch (r.frequency) {
      'daily' => 30.4 / r.interval,
      'weekly' => 4.35 / r.interval,
      'yearly' => 1 / (12 * r.interval),
      _ => 1 / r.interval,
    };
    total += r.amountMinor * per;
  }
  return total.round();
}
