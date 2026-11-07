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
        Text(tr('Ещё'), style: Theme.of(context).textTheme.headlineLarge),
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
          title: tr('Деньги'),
          children: [
            row(
              'accounts',
              Icons.account_balance_wallet_rounded,
              TileColors.blue,
              tr('Счета'),
              tr('Карты, наличные и вклады'),
              const AccountsScreen(),
              value: count(d.accounts.where((a) => !a.archived).length),
            ),
            row(
              'goals',
              Icons.star_rounded,
              TileColors.orange,
              tr('Мечты'),
              tr('Цели и накопления'),
              const GoalsScreen(),
              value: count(d.goals.length),
            ),
            row(
              'recurring',
              Icons.event_repeat_rounded,
              TileColors.purple,
              tr('Платежи и подписки'),
              tr('Кредиты, аренда, подписки, доходы'),
              const RecurringScreen(),
              value: count(d.recurring.where((r) => r.enabled).length),
            ),
          ],
        ),
        GroupedSection(
          title: tr('Планирование'),
          children: [
            row(
              'budgets',
              Icons.pie_chart_rounded,
              TileColors.green,
              tr('Бюджеты'),
              tr('Расходы в пределах плана'),
              const BudgetsScreen(),
              value: count(d.budgets.length),
            ),
            // 1.38: what to buy.
            row(
              'shopping',
              Icons.shopping_basket_rounded,
              TileColors.orange,
              tr('Список покупок'),
              tr('Что купить и сколько это стоит'),
              const ShoppingScreen(),
              value: count(d.shopping.where((s) => !s.done).length),
            ),
            row(
              'calendar',
              Icons.calendar_month_rounded,
              TileColors.red,
              tr('Календарь'),
              tr('Операции и платежи по датам'),
              const CalendarScreen(),
            ),
            row(
              'categories',
              Icons.category_rounded,
              TileColors.teal,
              tr('Категории'),
              tr('Доходы, расходы и иконки'),
              const CategoriesScreen(),
              value: count(d.categories.where((x) => !x.archived).length),
            ),
          ],
        ),
        GroupedSection(
          title: tr('Общее'),
          children: [
            // 1.44: achievements.
            row(
              'achievements',
              Icons.emoji_events_rounded,
              TileColors.orange,
              tr('Достижения'),
              tr('Награды за порядок в деньгах'),
              const AchievementsScreen(),
              value: '${c.achievements.unlockedCount}/${c.achievements.total}',
            ),
            row(
              'members',
              Icons.people_alt_rounded,
              TileColors.pink,
              tr('Семья'),
              tr('Участники общего бюджета'),
              const MembersScreen(),
              value: count(d.members.length),
            ),
            row(
              'settings',
              Icons.settings_rounded,
              TileColors.gray,
              tr('Настройки'),
              tr('Вид, защита, копии и обучение'),
              const SettingsScreen(),
            ),
          ],
        ),
      ],
    );
  }
}
