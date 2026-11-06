part of 'management.dart';

/// The «Ещё» tab (1.26): everything else, grouped like the iPhone settings.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final d = c.data;
    void open(Widget page) => openFinancePage(context, page);
    String count(int n) => n == 0 ? '' : '$n';
    GroupedRow row(
      String id,
      IconData icon,
      Color color,
      String title,
      String subtitle,
      Widget page, {
      String? value,
    }) => GroupedRow(
      key: ValueKey('more-$id'),
      icon: icon,
      color: color,
      title: title,
      subtitle: subtitle,
      value: value == null || value.isEmpty ? null : value,
      onTap: () => open(page),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
      children: [
        Text('Ещё', style: Theme.of(context).textTheme.headlineLarge),
        if (d.demo)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Сейчас показан пример',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 20),
        GroupedSection(
          title: 'Деньги',
          children: [
            row(
              'accounts',
              Icons.account_balance_wallet_rounded,
              TileColors.blue,
              'Счета',
              'Карты, наличные и вклады',
              const AccountsScreen(),
              value: count(d.accounts.where((a) => !a.archived).length),
            ),
            row(
              'goals',
              Icons.star_rounded,
              TileColors.orange,
              'Мечты',
              'Цели и накопления',
              const GoalsScreen(),
              value: count(d.goals.length),
            ),
            row(
              'recurring',
              Icons.event_repeat_rounded,
              TileColors.purple,
              'Подписки и платежи',
              'Регулярные списания и доходы',
              const RecurringScreen(),
              value: count(d.recurring.where((r) => r.enabled).length),
            ),
          ],
        ),
        GroupedSection(
          title: 'Планирование',
          children: [
            row(
              'budgets',
              Icons.pie_chart_rounded,
              TileColors.green,
              'Бюджеты',
              'Расходы в пределах плана',
              const BudgetsScreen(),
              value: count(d.budgets.length),
            ),
            row(
              'calendar',
              Icons.calendar_month_rounded,
              TileColors.red,
              'Календарь',
              'Операции и платежи по датам',
              const CalendarScreen(),
            ),
            row(
              'categories',
              Icons.category_rounded,
              TileColors.teal,
              'Категории',
              'Доходы, расходы и иконки',
              const CategoriesScreen(),
              value: count(d.categories.where((x) => !x.archived).length),
            ),
          ],
        ),
        GroupedSection(
          title: 'Общее',
          children: [
            row(
              'members',
              Icons.people_alt_rounded,
              TileColors.pink,
              'Семья',
              'Участники общего бюджета',
              const MembersScreen(),
              value: count(d.members.length),
            ),
            row(
              'settings',
              Icons.settings_rounded,
              TileColors.gray,
              'Настройки',
              'Вид, защита, копии и обучение',
              const SettingsScreen(),
            ),
          ],
        ),
      ],
    );
  }
}
