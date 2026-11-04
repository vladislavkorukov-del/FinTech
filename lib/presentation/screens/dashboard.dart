import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/finance_engine.dart';
import '../../domain/models.dart';
import '../controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/charts.dart';
import '../widgets/entry_tile.dart';
import 'management.dart';
import 'entry_editor.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({
    super.key,
    required this.onTransactions,
    required this.onAnalytics,
  });
  final VoidCallback onTransactions, onAnalytics;
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = AppTheme.accent(c.data.preferences.accent);
    final totals = FinanceEngine.totals(
      c.data.entries,
      c.periodStart,
      c.periodEnd,
      c.currency,
    );
    final prevStart = DateTime(
      c.periodStart.year,
      c.periodStart.month - 1,
      c.periodStart.day,
    );
    final prev = FinanceEngine.totals(
      c.data.entries,
      prevStart,
      c.periodStart,
      c.currency,
    );
    final change = prev.expense == 0
        ? null
        : (totals.expense - prev.expense) / prev.expense * 100;
    final recent = [...c.data.entries]
      ..sort((a, b) => b.date.compareTo(a.date));
    final cats = FinanceEngine.categoryTotals(
      c.data.entries,
      c.periodStart,
      c.periodEnd,
      c.currency,
      EntryKind.expense,
    ).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final accounts = c.data.accounts.where((a) => !a.archived).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(Icons.blur_on_rounded, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FINORA', style: theme.textTheme.labelSmall),
                  Text('Мои финансы', style: theme.textTheme.headlineSmall),
                ],
              ),
            ),
            IconButton(
              tooltip: c.hidden ? 'Показать суммы' : 'Скрыть суммы',
              onPressed: () async {
                try {
                  await c.preferences(
                    c.data.preferences.copyWith(hideAmounts: !c.hidden),
                  );
                } catch (e) {
                  if (context.mounted) {
                    showError(context, e);
                  }
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
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent,
                Color.lerp(accent, const Color(0xFFE4D9B8), .6)!,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .1),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFF182011)),
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
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      c.currency,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    money(c.balance, c.currency, c.hidden),
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.north_east_rounded, size: 17),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Разница за месяц: ${totals.net >= 0 ? '+' : ''}${money(totals.net, c.currency, c.hidden)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Активные счета в выбранной валюте',
                  style: TextStyle(fontSize: 10, color: Color(0xFF455234)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _Metric(
                'Доходы',
                totals.income,
                c.currency,
                c.hidden,
                Icons.south_west_rounded,
                const Color(0xFF8DBF9D),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                'Расходы',
                totals.expense,
                c.currency,
                c.hidden,
                Icons.north_east_rounded,
                const Color(0xFFD6B58E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            for (final item in [
              (EntryKind.expense, 'Расход', Icons.remove_rounded),
              (EntryKind.income, 'Доход', Icons.add_rounded),
              (EntryKind.transfer, 'Перевод', Icons.swap_horiz_rounded),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: OutlinedButton(
                    onPressed: () => showEntryEditor(context, kind: item.$1),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 4,
                      ),
                      side: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: .4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(item.$3, size: 22),
                        const SizedBox(height: 6),
                        Text(item.$2, style: const TextStyle(fontSize: 12)),
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
                    'Демопрофиль · данные для знакомства',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SectionTitle(
          'Обзор месяца',
          action: DateFormat('LLLL', 'ru').format(DateTime.now()),
        ),
        SurfaceCard(
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
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (ctx, constraints) => Row(
                  children: [
                    SizedBox(
                      width: constraints.maxWidth * .43,
                      child: DonutChart(
                        values: cats.map((e) => e.value).toList(),
                        colors: cats
                            .map(
                              (e) => Color(
                                c.category(e.key)?.color ??
                                    categoryColors.first,
                              ),
                            )
                            .toList(),
                        center: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${cats.length}',
                              style: theme.textTheme.headlineSmall,
                            ),
                            const Text(
                              'категорий',
                              style: TextStyle(fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        children: [
                          for (final e in cats.take(3))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: Color(
                                        c.category(e.key)?.color ??
                                            categoryColors.first,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      c.category(e.key)?.name ?? 'Прочее',
                                      style: const TextStyle(fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${totals.expense == 0 ? 0 : (e.value / totals.expense * 100).round()}%',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (change != null) ...[
                const SizedBox(height: 12),
                Text(
                  'На ${change.abs().round()}% ${change <= 0 ? 'меньше' : 'больше'}, чем в прошлом месяце',
                  style: TextStyle(
                    fontSize: 12,
                    color: change <= 0
                        ? const Color(0xFF8DBF9D)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Добавьте операции за прошлый месяц для сравнения',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        SectionTitle(
          'Мои счета',
          action: 'Все счета',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
          ),
        ),
        if (accounts.isEmpty)
          const EmptyState(
            'Добавьте первый счёт',
            'Банковская карта, наличные или накопления.',
          )
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: accounts.length,
              separatorBuilder: (_, i) => const SizedBox(width: 12),
              itemBuilder: (ctx, i) {
                final a = accounts[i];
                return SizedBox(
                  width: 232,
                  child: SurfaceCard(
                    color: Color.lerp(scheme.surface, Color(a.color), .1),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountsScreen(),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CategoryBadge(
                              icon: categoryIcon(a.icon),
                              color: Color(a.color),
                              size: 32,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          money(
                            FinanceEngine.balance(a, c.data.entries),
                            a.currency,
                            c.hidden,
                          ),
                          style: theme.textTheme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          a.lastFour.isEmpty
                              ? a.currency
                              : '•••• ${a.lastFour}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
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
                  'Добавьте доход или расход кнопкой +.',
                )
              : Column(
                  children: recent.take(5).map((e) => EntryTile(e)).toList(),
                ),
        ),
        SectionTitle(
          'Бюджет под контролем',
          action: 'Настроить',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const BudgetsScreen()),
          ),
        ),
        if (c.data.budgets.isEmpty)
          SurfaceCard(
            child: Text(
              'Установите месячный лимит и следите за расходами.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          )
        else
          ...c.data.budgets.take(2).map((b) {
            final spent = FinanceEngine.budgetSpent(
              b,
              c.data.entries,
              c.periodStart,
              c.periodEnd,
            );
            final ratio = b.limitMinor == 0 ? 0.0 : spent / b.limitMinor;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            b.name,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '${(ratio * 100).round()}%',
                          style: TextStyle(
                            color: ratio >= .9 ? scheme.error : scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: ratio.clamp(0, 1),
                        minHeight: 7,
                        color: ratio >= .9 ? scheme.error : scheme.primary,
                        backgroundColor: scheme.primary.withValues(alpha: .1),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${money(spent, b.currency, c.hidden)} из ${money(b.limitMinor, b.currency, c.hidden)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        SectionTitle(
          'Ближе к мечте',
          action: 'Все цели',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const GoalsScreen()),
          ),
        ),
        if (c.data.goals.isEmpty)
          const SurfaceCard(
            child: Text(
              'Создайте цель — отпуск, подушку безопасности или большую покупку.',
            ),
          )
        else
          ...c.data.goals
              .take(2)
              .map(
                (g) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SurfaceCard(
                    child: Row(
                      children: [
                        CategoryBadge(
                          icon: categoryIcon(g.icon),
                          color: Color(g.color),
                          size: 48,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(g.name, style: theme.textTheme.titleMedium),
                              const SizedBox(height: 6),
                              Text(
                                '${money(g.savedMinor, g.currency, c.hidden)} · ${g.targetMinor == 0 ? 0 : (g.savedMinor / g.targetMinor * 100).round()}% накоплено',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        SectionTitle(
          'По расписанию',
          action: 'Все',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const RecurringScreen()),
          ),
        ),
        ...([...c.data.recurring.where((r) => r.enabled)]
              ..sort((a, b) => a.nextDate.compareTo(b.nextDate)))
            .take(3)
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SurfaceCard(
                  child: Row(
                    children: [
                      CategoryBadge(
                        category: c.category(r.categoryId),
                        icon: Icons.event_repeat_outlined,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name, style: theme.textTheme.titleMedium),
                            Text(
                              DateFormat('d MMMM', 'ru').format(r.nextDate),
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        money(r.amountMinor, r.currency, c.hidden),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        const SizedBox(height: 18),
        Text(
          'Уверенность начинается с ясности.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
    this.label,
    this.amount,
    this.currency,
    this.hidden,
    this.icon,
    this.color,
  );
  final String label, currency;
  final int amount;
  final bool hidden;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
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
