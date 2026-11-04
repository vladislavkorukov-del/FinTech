part of 'management.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final routes =
        <({String title, String subtitle, IconData icon, Widget page})>[
          (
            title: 'Счета',
            subtitle: 'Карты, наличные и вклады',
            icon: Icons.wallet_outlined,
            page: const AccountsScreen(),
          ),
          (
            title: 'Категории',
            subtitle: 'Ваш порядок в финансах',
            icon: Icons.grid_view_rounded,
            page: const CategoriesScreen(),
          ),
          (
            title: 'Бюджеты',
            subtitle: 'Расходы в пределах плана',
            icon: Icons.pie_chart_outline_rounded,
            page: const BudgetsScreen(),
          ),
          (
            title: 'Накопления',
            subtitle: 'Ближе к вашим целям',
            icon: Icons.savings_outlined,
            page: const GoalsScreen(),
          ),
          (
            title: 'Регулярные платежи',
            subtitle: 'Подписки и обязательства',
            icon: Icons.update_rounded,
            page: const RecurringScreen(),
          ),
          (
            title: 'Календарь',
            subtitle: 'Финансы день за днём',
            icon: Icons.calendar_month_outlined,
            page: const CalendarScreen(),
          ),
          (
            title: 'Семья',
            subtitle: 'Участники общего бюджета',
            icon: Icons.people_outline_rounded,
            page: const MembersScreen(),
          ),
          (
            title: 'Настройки',
            subtitle: 'Стиль, защита и резервные копии',
            icon: Icons.tune_rounded,
            page: const SettingsScreen(),
          ),
        ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
      children: [
        Text(
          'Больше возможностей',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        Text(
          c.data.demo
              ? 'Демонстрационный профиль'
              : 'Ваше финансовое пространство',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 26),
        ...routes.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SurfaceCard(
              padding: const EdgeInsets.all(16),
              onTap: () => openFinancePage(context, r.page),
              child: Row(
                children: [
                  CategoryBadge(
                    icon: r.icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          r.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
