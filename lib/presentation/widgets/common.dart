import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';

abstract final class FinanceFormat {
  static String numberPattern = 'space_comma';
  static String datePattern = 'dd.MM.yyyy';
}

String decimalMinor(int value) =>
    '${value < 0 ? '-' : ''}${value.abs() ~/ 100}.${(value.abs() % 100).toString().padLeft(2, '0')}';
String displayDate(DateTime value) =>
    DateFormat(FinanceFormat.datePattern, 'ru').format(value);

String money(int value, [String currency = 'RUB', bool hidden = false]) {
  if (hidden) {
    return '••••••';
  }
  final symbol = switch (currency) {
    'RUB' => '₽',
    'USD' => '\$',
    'EUR' => '€',
    'CNY' => '¥',
    'TRY' => '₺',
    'GEL' => '₾',
    _ => currency,
  };
  final absolute = value.abs();
  final whole = absolute ~/ 100;
  final fraction = absolute % 100;
  final english = FinanceFormat.numberPattern == 'comma_dot';
  final grouped = NumberFormat('#,##0', english ? 'en_US' : 'ru').format(whole);
  final decimals = fraction == 0
      ? ''
      : '${english ? '.' : ','}${fraction.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}';
  return '${value < 0 ? '−' : ''}$grouped$decimals $symbol';
}

const currencies = [
  'RUB',
  'USD',
  'EUR',
  'CNY',
  'TRY',
  'GEL',
  'GBP',
  'AED',
  'KZT',
  'CHF',
];
const iconChoices = <IconData>[
  Icons.shopping_basket_outlined,
  Icons.restaurant_outlined,
  Icons.directions_bus_outlined,
  Icons.directions_car_outlined,
  Icons.home_outlined,
  Icons.bolt_outlined,
  Icons.favorite_border_rounded,
  Icons.medication_outlined,
  Icons.movie_outlined,
  Icons.subscriptions_outlined,
  Icons.shopping_bag_outlined,
  Icons.checkroom_outlined,
  Icons.card_giftcard_outlined,
  Icons.flight_outlined,
  Icons.school_outlined,
  Icons.child_care_outlined,
  Icons.pets_outlined,
  Icons.receipt_long_outlined,
  Icons.credit_card_outlined,
  Icons.more_horiz_rounded,
  Icons.work_outline_rounded,
  Icons.laptop_outlined,
  Icons.storefront_outlined,
  Icons.percent_rounded,
  Icons.trending_up_rounded,
  Icons.undo_rounded,
  Icons.wallet_outlined,
  Icons.savings_outlined,
  Icons.account_balance_outlined,
  Icons.beach_access_outlined,
  Icons.devices_outlined,
  Icons.shield_outlined,
  Icons.sports_esports_outlined,
  Icons.fitness_center_outlined,
  Icons.coffee_outlined,
  Icons.music_note_outlined,
];
const categoryColors = [
  0xFFA8C889,
  0xFFD5B995,
  0xFF94B8D4,
  0xFFB2A0CF,
  0xFFE5A58F,
  0xFF84C4B3,
  0xFFE0C77B,
  0xFFCC9DAF,
];
IconData categoryIcon(int index) =>
    iconChoices[index.abs() % iconChoices.length];

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: .16),
          ),
        ),
        child: child,
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ],
    ),
  );
}

class CategoryBadge extends StatelessWidget {
  const CategoryBadge({
    super.key,
    this.category,
    this.icon,
    this.color,
    this.size = 44,
  });
  final Category? category;
  final IconData? icon;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Color(category?.color ?? 0xFF94B8D4);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: category == null
            ? c.withValues(alpha: .14)
            : Color(category!.background),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(
        icon ?? categoryIcon(category?.icon ?? 26),
        color: c,
        size: 22,
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(
    this.title,
    this.description, {
    super.key,
    this.icon = Icons.inbox_outlined,
  });
  final String title, description;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      children: [
        Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    ) ??
    false;
void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error is FormatException
            ? error.message
            : 'Не удалось выполнить действие. $error',
      ),
    ),
  );
}
