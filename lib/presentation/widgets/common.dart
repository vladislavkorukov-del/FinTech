import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../theme/icon_catalog.dart';
export '../theme/icon_catalog.dart';

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
        if (action != null)
          if (onTap != null)
            TextButton(onPressed: onTap, child: Text(action!))
          else
            Flexible(
              child: Text(
                action!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
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
    final scheme = Theme.of(context).colorScheme;
    final c =
        color ?? (category == null ? scheme.onSurface : Color(category!.color));
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
