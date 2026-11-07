import '../i18n.dart';
import 'package:flutter/material.dart';

import '../../domain/finance_engine.dart';
import '../controller.dart';
import '../screens/management.dart';
import 'common.dart';

/// Currency names for the sheet.
const currencyNames = <String, String>{
  'RUB': 'Российский рубль',
  'USD': 'Доллар США',
  'EUR': 'Евро',
  'CNY': 'Китайский юань',
  'TRY': 'Турецкая лира',
  'GEL': 'Грузинский лари',
  'GBP': 'Фунт стерлингов',
  'AED': 'Дирхам ОАЭ',
  'KZT': 'Казахстанский тенге',
  'CHF': 'Швейцарский франк',
};

/// Tapping the balance in the header (1.28): the balance, income and expenses
/// in another currency at the person's own rates. Finora never goes online,
/// so the rates are set here by hand (rough ones to start).
Future<void> showCurrencySheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CurrencySheet(),
    );

class _CurrencySheet extends StatelessWidget {
  const _CurrencySheet();

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final p = c.data.preferences;
    final scheme = Theme.of(context).colorScheme;
    final shown = p.shownCurrency;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: ListView(
          key: const ValueKey('currency-sheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              tr('Показать в валюте'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Баланс, доходы и расходы месяца на главной — в выбранной '
              'валюте. Данные не меняются.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            for (final code in currencies)
              _row(context, c, code, selected: code == shown),
            const SizedBox(height: 8),
            Text(
              'Курсы задаёте вы: Finora не выходит в интернет. Сначала стоят '
              'ориентировочные — нажмите на курс, чтобы поправить.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('currency-accounts'),
              onPressed: () {
                Navigator.pop(context);
                openFinancePage(context, const AccountsScreen());
              },
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(tr('Открыть счета')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    FinanceController c,
    String code, {
    required bool selected,
  }) {
    final p = c.data.preferences;
    final scheme = Theme.of(context).colorScheme;
    final base = p.baseCurrency;
    final shown = p.copyWith(displayCurrency: code).toDisplay(c.balance);
    final rate = p.rubles(code) / p.rubles(base);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        key: ValueKey('currency-$code'),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        onTap: () {
          c.preferences(
            c.data.preferences.copyWith(
              displayCurrency: code == base ? '' : code,
            ),
          );
          Navigator.pop(context);
        },
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    money(shown, code),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    currencyNames[code] ?? code,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (code != base)
              Flexible(
                child: TextButton(
                  key: ValueKey('currency-rate-$code'),
                  onPressed: () => _editRate(context, c, code),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '1 $code = ${_number(rate)} $base',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _number(double v) => v >= 100
      ? v.toStringAsFixed(0)
      : v >= 1
      ? v.toStringAsFixed(2).replaceAll('.', ',')
      : v.toStringAsFixed(4).replaceAll('.', ',');

  Future<void> _editRate(
    BuildContext context,
    FinanceController c,
    String code,
  ) async {
    final p = c.data.preferences;
    final base = p.baseCurrency;
    final field = TextEditingController(
      text: _number(p.rubles(code) / p.rubles(base)),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Курс $code'),
        content: TextField(
          key: const ValueKey('currency-rate-field'),
          controller: field,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            prefixText: '1 $code = ',
            suffixText: base,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('currency-rate-save'),
            onPressed: () {
              final v = double.tryParse(
                field.text.replaceAll(' ', '').replaceAll(',', '.'),
              );
              Navigator.pop(ctx, v != null && v > 0 ? v : null);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    field.dispose();
    if (value == null) return;
    // Stored as rubles per unit.
    final rubles = value * p.rubles(base);
    await c.preferences(
      c.data.preferences.copyWith(
        rates: {...c.data.preferences.rates, code: rubles},
      ),
    );
  }
}

/// Month totals converted for display.
({int income, int expense}) displayTotals(FinanceController c) {
  final t = FinanceEngine.totals(
    c.data.entries,
    c.periodStart,
    c.periodEnd,
    c.currency,
  );
  final p = c.data.preferences;
  return (income: p.toDisplay(t.income), expense: p.toDisplay(t.expense));
}
